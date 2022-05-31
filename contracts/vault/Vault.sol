// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
/**
 * @title  Vault Contract
 * @notice The Vault contract defines the storage for the Vault contracts
 * @author BankOfChain Protocol Inc
 */
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./VaultStorage.sol";
import "../library/BocRoles.sol";
import "../strategy/IStrategy.sol";
import "../exchanges/IExchangeAggregator.sol";
import "../price-feeds/IValueInterpreter.sol";

contract Vault is VaultStorage {
    using StableMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using IterableIntMap for IterableIntMap.AddressToIntMap;

    function initialize(
        address _accessControlProxy,
        address _treasury,
        address _exchangeManager,
        address _valueInterpreter
    ) public initializer {
        _initAccessControl(_accessControlProxy);

        treasury = _treasury;
        exchangeManager = _exchangeManager;
        valueInterpreter = _valueInterpreter;

        rebasePaused = false;
        // Initial redeem fee of 0 basis points
        redeemFeeBps = 0;
        // Threshold for rebasing
        rebaseThreshold = 1000e18;
    }

    modifier whenNotEmergency() {
        require(!emergencyShutdown, "ES");
        _;
    }

    modifier whenNotAdjustPosition() {
        require(!adjustPositionPeriod, "AD");
        _;
    }

    /**
     * @dev Verifies that the rebasing is not paused.
     */
    modifier whenNotRebasePaused() {
        require(!rebasePaused, "RP");
        _;
    }

    modifier isActiveStrategy(address _strategy) {
        checkActiveStrategy(_strategy);
        _;
    }

    /// @notice Version of vault
    function getVersion() external pure returns (string memory) {
        return "1.0.0";
    }

    /// @notice Minting USDi supported assets
    function getSupportAssets() external view returns (address[] memory) {
        return assetSet.values();
    }

    function checkIsSupportAsset(address _asset) public view {
        require(assetSet.contains(_asset), "The asset not support");
    }

    /// @notice Assets held by Vault
    function getTrackedAssets() external view returns (address[] memory) {
        return _getTrackedAssets();
    }

    /// @notice Assets held by Vault
    function _getTrackedAssets() internal view returns (address[] memory) {
        return trackedAssetsMap._inner._keys.values();
    }

    /// @notice Vault holds asset value directly in USD (1e18)
    function valueOfTrackedTokens() external view returns (uint256) {
        return _totalValueInVault();
    }

    /// @notice Vault total asset in USD(1e18)
    function totalAssets() external view returns (uint256) {
        return _totalValueInVault() + totalDebt;
    }

    /// @notice Vault total value(by chainlink price) in USD(1e18)
    function totalValue() external view returns (uint256) {
        return _totalValueInVault() + totalValueInStrategies();
    }

    /**
     * @dev Internal to calculate total value of all assets held in Vault.
     * @return Total value(by chainlink price) in USD (1e18)
     */
    function totalValueInVault() external view returns (uint256) {
        return _totalValueInVault();
    }

    function _totalValueInVault() internal view returns (uint256 _value) {
        address[] memory _trackedAssets = _getTrackedAssets();
        for (uint256 i = 0; i < _trackedAssets.length; i++) {
            address _trackedAsset = _trackedAssets[i];
            uint256 balance = balanceOfToken(_trackedAsset, address(this));
            if (balance > 0) {
                _value =
                    _value +
                    IValueInterpreter(valueInterpreter)
                        .calcCanonicalAssetValueInUsd(_trackedAsset, balance);
            }
        }
    }

    /**
     * @dev Internal to calculate total value of all assets held in Strategies.
     * @return _value Total value(by chainlink price) in USD (1e18)
     */
    function totalValueInStrategies() public view returns (uint256 _value) {
        uint256 _strategyLength = strategySet.length();
        for (uint256 i = 0; i < _strategyLength; i++) {
            uint256 estimatedTotalAssets = IStrategy(strategySet.at(i))
                .estimatedTotalAssets();
            if (estimatedTotalAssets > 0) {
                _value = _value + estimatedTotalAssets;
            }
        }
    }

    /// @notice All strategies
    function getStrategies() external view returns (address[] memory) {
        return strategySet.values();
    }

    function checkActiveStrategy(address _strategy) public view {
        require(strategySet.contains(_strategy), "strategy not exist");
    }

    /// @notice estimate Minting USDi with stablecoins
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @dev Support single asset or multi-assets
    /// @return priceAdjustedDeposit usdi amount
    function estimateMint(address[] memory _assets, uint256[] memory _amounts)
        public
        view
        returns (uint256 priceAdjustedDeposit)
    {
        require(
            _assets.length > 0 &&
                _amounts.length > 0 &&
                _assets.length == _amounts.length,
            "Assets and amounts must be equal in length and not empty"
        );

        for (uint256 i = 0; i < _assets.length; i++) {
            checkIsSupportAsset(_assets[i]);
            require(_amounts[i] > 0, "Amount must be greater than 0");
        }

        for (uint256 i = 0; i < _assets.length; i++) {
            address _asset = _assets[i];
            uint256 price = _priceUSDMint(_asset);
            uint256 assetDecimals = trackedAssetDecimalsMap[_asset];
            priceAdjustedDeposit =
                priceAdjustedDeposit +
                (_amounts[i].mulTruncateScale(price, 10**assetDecimals));
        }
        return priceAdjustedDeposit;
    }

    /// @notice Minting USDi with stablecoins
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @param _minimumUsdiAmount Minimum USDI to mint
    /// @dev Support single asset or multi-assets
    function mint(
        address[] memory _assets,
        uint256[] memory _amounts,
        uint256 _minimumUsdiAmount
    )
        external
        whenNotEmergency
        whenNotAdjustPosition
        nonReentrant
        returns (uint256)
    {
        uint256 priceAdjustedDeposit = estimateMint(_assets, _amounts);
        if (_minimumUsdiAmount > 0) {
            require(
                priceAdjustedDeposit >= _minimumUsdiAmount,
                "Mint amount lower than minimum"
            );
        }

        // Rebase must happen before any transfers occur.
        if (priceAdjustedDeposit >= rebaseThreshold && !rebasePaused) {
            _rebase();
        }

        // Mint matching USDi
        usdi.mint(msg.sender, priceAdjustedDeposit);

        for (uint256 i = 0; i < _assets.length; i++) {
            // Transfer the deposited coins to the vault
            IERC20Upgradeable asset = IERC20Upgradeable(_assets[i]);
            asset.safeTransferFrom(msg.sender, address(this), _amounts[i]);
        }

        emit Mint(msg.sender, _assets, _amounts, priceAdjustedDeposit);
        return priceAdjustedDeposit;
    }

    /// @notice withdraw from strategy queue
    function _repayFromWithdrawQueue(uint256 needWithdrawValue) internal {
        uint256 totalWithdrawValue;
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            address _strategy = withdrawQueue[i];
            if (_strategy == ZERO_ADDRESS) break;

            //            uint256 strategyTotalValue = _checkValueInStrategyByRedeem(_strategy, _assetDecimals, _assetRedeemPrices);
            uint256 strategyTotalValue = strategies[_strategy].totalDebt;
            if (strategyTotalValue <= 0) {
                continue;
            }

            uint256 strategyWithdrawValue;
            if (needWithdrawValue > strategyTotalValue) {
                strategyWithdrawValue = strategyTotalValue;
                needWithdrawValue -= strategyWithdrawValue;
            } else {
                strategyWithdrawValue = needWithdrawValue;
                needWithdrawValue = 0;
            }
            // console.log('start withdrawn from %s numerator %d denominator %d', _strategy, strategyWithdrawValue, strategyTotalValue);
            (address[] memory _assets, uint256[] memory _amounts) = IStrategy(
                _strategy
            ).repay(strategyWithdrawValue, strategyTotalValue);
            emit RepayFromStrategy(
                _strategy,
                strategyWithdrawValue,
                strategyTotalValue,
                _assets,
                _amounts
            );

            strategies[_strategy].totalDebt -= strategyWithdrawValue;
            totalWithdrawValue += strategyWithdrawValue;

            if (needWithdrawValue <= 0) {
                break;
            }
        }
        totalDebt -= totalWithdrawValue;
    }

    /// @notice calculate need transfer amount from vault ,set to outputs
    function _calculateOutputs(
        uint256 _needTransferAmount,
        address[] memory _trackedAssets,
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals
    ) internal view returns (uint256[] memory) {
        uint256 _needTransferAmountCopy = _needTransferAmount;
        address[] memory _trackedAssetsCopy = _trackedAssets;
        uint256 _trackedAssetsLength = _trackedAssetsCopy.length;
        uint256[] memory outputs = new uint256[](_trackedAssetsLength);

        (
            uint256[] memory outPutAssetPriceSortedAssetIndex,
            uint256[] memory outPutAssetBalance,
            uint256 _sortedAssetCount
        ) = _calculateSortedAssets(_trackedAssetsCopy, _assetPrices);

        for (uint256 i = 0; i < _sortedAssetCount; i++) {
            uint256 index = outPutAssetPriceSortedAssetIndex[i];
            address trackedAsset = _trackedAssetsCopy[index];
            uint256 balance = outPutAssetBalance[index];

            (, uint256 _assetRedeemPrice) = _getAssetRedeemPrice(
                _assetPrices,
                index,
                trackedAsset
            );
            uint256 _assetDecimal = _getAssetDecimals(
                _assetDecimals,
                index,
                trackedAsset
            );

            uint256 _value = balance.mulTruncateScale(
                _assetRedeemPrice,
                10**_assetDecimal
            );
            if (_value >= _needTransferAmountCopy) {
                outputs[index] = (balance * _needTransferAmountCopy) / _value;
                break;
            } else {
                outputs[index] = balance;
                _needTransferAmountCopy = _needTransferAmountCopy - _value;
            }
        }
        return outputs;
    }

    /// @notice calculate need transfer amount from vault ,set to outputs order by oracle price
    function _calculateSortedAssets(
        address[] memory _trackedAssets,
        uint256[] memory _assetPrices
    )
        internal
        view
        returns (
            uint256[] memory outPutAssetPriceSortedAssetIndex,
            uint256[] memory outPutAssetBalance,
            uint256 _sortedAssetCount
        )
    {
        address[] memory _trackedAssetsCopy = _trackedAssets;
        uint256 _trackedAssetsLength = _trackedAssetsCopy.length;

        outPutAssetBalance = new uint256[](_trackedAssetsLength);
        outPutAssetPriceSortedAssetIndex = new uint256[](_trackedAssetsLength);
        for (uint256 i = 0; i < _trackedAssetsLength; i++) {
            address trackedAsset = _trackedAssetsCopy[i];
            uint256 balance = balanceOfToken(trackedAsset, address(this));
            if (balance > 0) {
                outPutAssetBalance[i] = balance;
                outPutAssetPriceSortedAssetIndex[_sortedAssetCount] = i;
                (uint256 _assetPrice, ) = _getAssetRedeemPrice(
                    _assetPrices,
                    i,
                    trackedAsset
                );
                for (uint256 j = 0; j < _sortedAssetCount; j++) {
                    uint256 _currentAssetIndex = outPutAssetPriceSortedAssetIndex[
                            j
                        ];
                    (
                        uint256 _currentSortedIndexAssetPrice,

                    ) = _getAssetRedeemPrice(
                            _assetPrices,
                            _currentAssetIndex,
                            _trackedAssetsCopy[_currentAssetIndex]
                        );
                    if (_assetPrice >= _currentSortedIndexAssetPrice) {
                        for (uint256 k = _sortedAssetCount; k > j; k--) {
                            outPutAssetPriceSortedAssetIndex[
                                k
                            ] = outPutAssetPriceSortedAssetIndex[k - 1];
                        }
                        outPutAssetPriceSortedAssetIndex[j] = i;
                        break;
                    }
                }
                _sortedAssetCount = _sortedAssetCount + 1;
            }
        }
    }

    // @notice exchange token to _asset form vault and transfer to user
    function _exchangeAndTransfer(
        address _asset,
        uint256[] memory _outputs,
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals,
        address[] memory _trackedAssets,
        IExchangeAggregator.ExchangeToken[] memory _exchangeTokens
    )
        internal
        returns (
            address[] memory _assets,
            uint256[] memory _amounts,
            uint256 _actualAmount
        )
    {
        address _assetCopy = _asset;
        uint256[] memory _assetPricesCopy = _assetPrices;
        uint256 _trackedAssetsLength = _trackedAssets.length;

        _assets = new address[](_trackedAssetsLength);
        _amounts = new uint256[](_trackedAssetsLength);
        uint256 _toTokenIndex = _trackedAssetsLength;
        uint256 _toTokenAmount;
        for (uint256 i = 0; i < _trackedAssetsLength; i++) {
            _assets[i] = _trackedAssets[i];
            if (
                _toTokenIndex == _trackedAssetsLength &&
                _assets[i] == _assetCopy
            ) {
                _toTokenIndex = i;
            }
            address withdrawToken = _assets[i];
            uint256 withdrawAmount = _outputs[i];
            if (withdrawAmount > 0) {
                if (withdrawToken == _assetCopy) {
                    _toTokenAmount = _toTokenAmount + withdrawAmount;
                } else {
                    _amounts[i] = withdrawAmount;
                    for (uint256 j = 0; j < _exchangeTokens.length; j++) {
                        IExchangeAggregator.ExchangeToken
                            memory exchangeToken = _exchangeTokens[j];
                        if (
                            exchangeToken.fromToken == withdrawToken &&
                            exchangeToken.toToken == _assetCopy
                        ) {
                            _amounts[i] = 0;
                            uint256 toAmount = _exchange(
                                exchangeToken.fromToken,
                                exchangeToken.toToken,
                                withdrawAmount,
                                exchangeToken.exchangeParam
                            );
                            // console.log('withdraw exchange token %s amount %d toAmount %d', withdrawAmount, withdrawAmount, toAmount);
                            _toTokenAmount = _toTokenAmount + toAmount;
                            break;
                        }
                    }
                }
            }
        }
        _amounts[_toTokenIndex] = _toTokenAmount;
        for (uint256 i = 0; i < _trackedAssetsLength; i++) {
            uint256 _amount = _amounts[i];
            if (_amount > 0) {
                address _trackedAsset = _assets[i];
                uint256 _toDecimal = _getAssetDecimals(
                    _assetDecimals,
                    i,
                    _trackedAsset
                );
                (uint256 _toPrice, ) = _getAssetRedeemPrice(
                    _assetPricesCopy,
                    i,
                    _trackedAsset
                );
                _actualAmount =
                    _actualAmount +
                    _amount.mulTruncateScale(_toPrice, 10**_toDecimal);
                IERC20Upgradeable(_trackedAsset).safeTransfer(
                    msg.sender,
                    _amount
                );
            }
        }
    }

    // @notice without exchange token and transfer form vault to user
    function _withoutExchangeTransfer(
        uint256[] memory _outputs,
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals,
        address[] memory _trackedAssets
    )
        internal
        returns (
            address[] memory _assets,
            uint256[] memory _amounts,
            uint256 _actualAmount
        )
    {
        _assets = _trackedAssets;
        _amounts = _outputs;
        for (uint256 i = 0; i < _assets.length; i++) {
            uint256 _amount = _amounts[i];
            if (_amount > 0) {
                address _trackedAsset = _assets[i];
                (uint256 _toPrice, ) = _getAssetRedeemPrice(
                    _assetPrices,
                    i,
                    _trackedAsset
                );
                _actualAmount =
                    _actualAmount +
                    _amount.mulTruncateScale(_toPrice, 10**_assetDecimals[i]);
                IERC20Upgradeable(_trackedAsset).safeTransfer(
                    msg.sender,
                    _amount
                );
            }
        }
    }

    /// @notice burn USDi,return stablecoins
    /// @param _amount Amount of USDi to burn
    /// @param _asset one of StableCoin asset
    /// @param _minimumUsdAmount Minimum usd to receive in return
    function burn(
        uint256 _amount,
        address _asset,
        uint256 _minimumUsdAmount,
        bool _needExchange,
        IExchangeAggregator.ExchangeToken[] memory _exchangeTokens
    )
        external
        whenNotEmergency
        whenNotAdjustPosition
        nonReentrant
        returns (address[] memory _assets, uint256[] memory _amounts)
    {
        IExchangeAggregator.ExchangeToken[]
            memory _exchangeTokensCopy = _exchangeTokens;
        {
            require(
                _amount > 0 && _amount <= usdi.balanceOf(msg.sender),
                "Amount must be greater than 0 and less than or equal to balance"
            );
            checkIsSupportAsset(_asset);

            for (uint256 i = 0; i < _exchangeTokensCopy.length; i++) {
                require(
                    _exchangeTokensCopy[i].toToken == _asset ||
                        _exchangeTokensCopy[i].toToken ==
                        _exchangeTokensCopy[i].fromToken,
                    "toToken is invalid"
                );
            }
        }

        uint256 _actualAmount = _amount;
        uint256 _redeemFee = 0;
        // Calculate redeem fee
        if (redeemFeeBps > 0) {
            _redeemFee = (_amount * redeemFeeBps) / 10000;
            _actualAmount = _amount - _redeemFee;
        }

        address[] memory _trackedAssets = _getTrackedAssets();
        uint256[] memory _assetPrices = new uint256[](_trackedAssets.length);
        uint256[] memory _assetDecimals = new uint256[](_trackedAssets.length);
        uint256 totalAssetInVault = 0;
        {
            //redeem price in vault
            for (uint256 i = 0; i < _trackedAssets.length; i++) {
                address _trackedAsset = _trackedAssets[i];
                uint256 _assetBalancesInVault = balanceOfToken(
                    _trackedAsset,
                    address(this)
                );
                if (_assetBalancesInVault > 0) {
                    (, uint256 _assetRedeemPrice) = _getAssetRedeemPrice(
                        _assetPrices,
                        i,
                        _trackedAsset
                    );
                    uint256 _assetDecimal = _getAssetDecimals(
                        _assetDecimals,
                        i,
                        _trackedAsset
                    );
                    totalAssetInVault =
                        totalAssetInVault +
                        (
                            _assetBalancesInVault.mulTruncateScale(
                                _assetRedeemPrice,
                                10**_assetDecimal
                            )
                        );
                }
            }

            // vault not enough,withdraw from withdraw queue strategy
            if (totalAssetInVault < _actualAmount) {
                _repayFromWithdrawQueue(_actualAmount - totalAssetInVault);
            }
        }

        uint256 _actuallyReceivedAmount = 0;
        {
            // calculate need transfer amount from vault ,set to outputs
            uint256[] memory outputs = _calculateOutputs(
                _actualAmount,
                _trackedAssets,
                _assetPrices,
                _assetDecimals
            );
            if (_needExchange) {
                (
                    _assets,
                    _amounts,
                    _actuallyReceivedAmount
                ) = _exchangeAndTransfer(
                    _asset,
                    outputs,
                    _assetPrices,
                    _assetDecimals,
                    _trackedAssets,
                    _exchangeTokensCopy
                );
            } else {
                (
                    _assets,
                    _amounts,
                    _actuallyReceivedAmount
                ) = _withoutExchangeTransfer(
                    outputs,
                    _assetPrices,
                    _assetDecimals,
                    _trackedAssets
                );
            }
        }

        if (_minimumUsdAmount > 0) {
            require(
                _actuallyReceivedAmount >= _minimumUsdAmount,
                "amount lower than minimum"
            );
        }
        _burnUSDIAndCheckRebase(
            _asset,
            _actualAmount + _redeemFee,
            _actuallyReceivedAmount
        );
    }

    // @notice burn usdi and check rebase
    function _burnUSDIAndCheckRebase(
        address _asset,
        uint256 _amount,
        uint256 _actualAmount
    ) internal {
        usdi.burn(msg.sender, _amount);

        // Until we can prove that we won't affect the prices of our assets
        // by withdrawing them, this should be here.
        // It's possible that a strategy was off on its asset total, perhaps
        // a reward token sold for more or for less than anticipated.
        if (_amount > rebaseThreshold && !rebasePaused) {
            _rebase();
        }
        emit Burn(msg.sender, _asset, _amount, _actualAmount);
    }

    /**
     * @notice Get the supported asset Decimal
     * @return _assetDecimal asset Decimals
     */
    function _getAssetDecimals(
        uint256[] memory _assetDecimals,
        uint256 _assetIndex,
        address _asset
    ) internal view returns (uint256) {
        if (_assetDecimals[_assetIndex] == 0) {
            _assetDecimals[_assetIndex] = trackedAssetDecimalsMap[_asset];
        }
        return _assetDecimals[_assetIndex];
    }

    /**
     * @notice Get an array of the supported asset prices in USD.
     * @return price prices in USD (1e18)
     * @return redeemPrice redeem prices in USD (1e18)
     */
    function _getAssetRedeemPrice(
        uint256[] memory _assetPrices,
        uint256 _assetIndex,
        address _asset
    ) internal view returns (uint256 price, uint256 redeemPrice) {
        if (_assetPrices[_assetIndex] == 0) {
            (_assetPrices[_assetIndex], redeemPrice) = priceUSDRedeem(_asset);
        } else {
            redeemPrice = priceInRedeem(_assetPrices[_assetIndex]);
        }
        price = _assetPrices[_assetIndex];
    }

    /// @notice Change USDi supply with Vault total assets.
    function rebase() external nonReentrant {
        _rebase();
    }

    /**
     * @dev Calculate the total value of assets held by the Vault and all
     *      strategies and update the supply of USDI, optionally sending a
     *      portion of the yield to the trustee.
     */
    function _rebase() internal whenNotEmergency whenNotRebasePaused {
        uint256 usdiSupply = usdi.totalSupply();
        if (usdiSupply == 0 || usdi.rebasingCredits() < 1e27) {
            return;
        }

        uint256 vaultValue = _totalValueInVault() + totalDebt;

        // Yield fee collection
        address _treasuryAddress = treasury;
        // gas savings
        if (
            trusteeFeeBps > 0 &&
            _treasuryAddress != address(0) &&
            (vaultValue > usdiSupply)
        ) {
            uint256 yield = vaultValue - usdiSupply;
            uint256 fee = (yield * trusteeFeeBps) / 10000;
            require(yield > fee, "Fee must not be greater than yield");
            if (fee > 0) {
                usdi.mint(_treasuryAddress, fee);
            }
        }

        // Only rachet USDi supply upwards
        usdiSupply = usdi.totalSupply();
        // Final check should use latest value
        if (vaultValue != usdiSupply) {
            usdi.changeSupply(vaultValue);
        }
    }

    /// @notice Allocate funds in Vault to strategies.
    function lend(
        address _strategy,
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    )
        external
        isKeeper
        whenNotEmergency
        isActiveStrategy(_strategy)
        nonReentrant
    {
        (
            address[] memory _wants,
            uint256[] memory _ratios,
            uint256[] memory toAmounts
        ) = _checkAndExchange(_strategy, _exchangeTokens);
        //Definition rule 0 means unconstrained, currencies that do not participate are not in the returned wants
        uint256 minProductIndex = 0;
        bool isWantRatioIgnorable = IStrategy(_strategy).isWantRatioIgnorable();
        if (!isWantRatioIgnorable && _ratios.length > 1) {
            for (uint256 i = 1; i < _ratios.length; i++) {
                // console.log('token %s amount %d aspect %d', _wants[i], toAmounts[i], _ratios[i]);
                // console.log('token i+1  %s amount %d aspect %d', tokenDetails[i + 1].token, tokenDetails[i + 1].amount, tokenAspects[i + 1].aspect);
                if (_ratios[i] == 0) {
                    //0 is free
                    continue;
                } else if (_ratios[minProductIndex] == 0) {
                    //minProductIndex is assigned to the first index whose proportion is not 0
                    minProductIndex = i;
                } else if (
                    toAmounts[minProductIndex] * _ratios[i] >
                    toAmounts[i] * _ratios[minProductIndex]
                ) {
                    minProductIndex = i;
                }
            }
        }

        uint256 minMount = toAmounts[minProductIndex];
        uint256 minAspect = _ratios[minProductIndex];
        uint256 lendValue;
        for (uint256 i = 0; i < toAmounts.length; i++) {
            uint256 _actualAmount = toAmounts[i];
            if (_actualAmount > 0) {
                address _want = _wants[i];
                // console.log('token %s amount %d', _wants[i], toAmounts[i]);
                // console.log(' minProductIndex %d minMount %d minAspect %d', minProductIndex, minMount, minAspect);

                if (!isWantRatioIgnorable && _ratios[i] > 0) {
                    _actualAmount = (_ratios[i] * minMount) / minAspect;
                }
                lendValue =
                    lendValue +
                    IValueInterpreter(valueInterpreter)
                        .calcCanonicalAssetValueInUsd(_want, _actualAmount);
                toAmounts[i] = _actualAmount;
                // console.log('token %s actual amount %d', _wants[i], actualAmount);
                IERC20Upgradeable(_want).safeTransfer(_strategy, _actualAmount);
            }
        }
        IStrategy strategy = IStrategy(_strategy);
        strategy.borrow(_wants, toAmounts);
        address[] memory _rewardTokens;
        uint256[] memory _claimAmounts;
        _report(_strategy, _rewardTokens, _claimAmounts, lendValue);
        emit LendToStrategy(_strategy, _wants, toAmounts, lendValue);
    }

    /// @notice check valid and exchange to want token
    function _checkAndExchange(
        address _strategy,
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    )
        internal
        returns (
            address[] memory _wants,
            uint256[] memory _ratios,
            uint256[] memory toAmounts
        )
    {
        (_wants, _ratios) = IStrategy(_strategy).getWantsInfo();
        uint256 _wantsLength = _wants.length;
        toAmounts = new uint256[](_wantsLength);
        uint256 _exchangeTokensLength = _exchangeTokens.length;
        for (uint256 i = 0; i < _exchangeTokensLength; i++) {
            bool findToToken = false;
            for (uint256 j = 0; j < _wantsLength; j++) {
                if (_exchangeTokens[i].toToken == _wants[j]) {
                    findToToken = true;
                    break;
                }
            }
            require(findToToken, "toToken invalid");
        }

        for (uint256 j = 0; j < _wantsLength; j++) {
            for (uint256 i = 0; i < _exchangeTokensLength; i++) {
                IExchangeAggregator.ExchangeToken
                    memory exchangeToken = _exchangeTokens[i];

                // not strategy need token,skip
                if (_wants[j] != exchangeToken.toToken) continue;

                uint256 toAmount;
                if (exchangeToken.fromToken == exchangeToken.toToken) {
                    toAmount = exchangeToken.fromAmount;
                } else {
                    if (exchangeToken.fromAmount > 0) {
                        toAmount = _exchange(
                            exchangeToken.fromToken,
                            exchangeToken.toToken,
                            exchangeToken.fromAmount,
                            exchangeToken.exchangeParam
                        );
                    }
                }

                toAmounts[j] = toAmount;
                break;
            }
        }
    }

    function exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory exchangeParam
    ) external isKeeper nonReentrant returns (uint256) {
        return _exchange(_fromToken, _toToken, _amount, exchangeParam);
    }

    function _exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory exchangeParam
    ) internal returns (uint256 exchangeAmount) {
        require(trackedAssetsMap.contains(_toToken), "!T");

        IExchangeAdapter.SwapDescription
            memory swapDescription = IExchangeAdapter.SwapDescription({
                amount: _amount,
                srcToken: _fromToken,
                dstToken: _toToken,
                receiver: address(this)
            });
        IERC20Upgradeable(_fromToken).safeApprove(exchangeManager, _amount);
        exchangeAmount = IExchangeAggregator(exchangeManager).swap(
            exchangeParam.platform,
            exchangeParam.method,
            exchangeParam.encodeExchangeArgs,
            swapDescription
        );
        uint256 oracleExpectedAmount = IValueInterpreter(valueInterpreter)
            .calcCanonicalAssetValue(_fromToken, _amount, _toToken);
        require(
            exchangeAmount >=
                (oracleExpectedAmount *
                    (MAX_BPS -
                        exchangeParam.slippage -
                        exchangeParam.oracleAdditionalSlippage)) /
                    MAX_BPS,
            "OL"
        );
        emit Exchange(
            exchangeParam.platform,
            _fromToken,
            _amount,
            _toToken,
            exchangeAmount
        );
    }

    /// @notice redeem the funds from specified strategy.
    function redeem(address _strategy, uint256 _amount)
        external
        isKeeper
        isActiveStrategy(_strategy)
        nonReentrant
    {
        uint256 strategyAssetValue = strategies[_strategy].totalDebt;
        require(_amount <= strategyAssetValue);

        IStrategy strategy = IStrategy(_strategy);
        (address[] memory _assets, uint256[] memory _amounts) = strategy.repay(
            _amount,
            strategyAssetValue
        );

        strategies[_strategy].totalDebt -= _amount;
        totalDebt -= _amount;

        // console.log('[vault.redeem] %s redeem _amount %d totalDebt %d ', _strategy, _amount, strategyAssetValue);
        emit Redeem(_strategy, _amount, _assets, _amounts);
    }

    function _report(
        address _strategy,
        address[] memory _rewardTokens,
        uint256[] memory _claimAmounts,
        uint256 lendValue
    ) private {
        StrategyParams memory strategyParam = strategies[_strategy];
        uint256 lastStrategyTotalDebt = strategyParam.totalDebt + lendValue;
        uint256 nowStrategyTotalDebt = IStrategy(_strategy)
            .estimatedTotalAssets();
        uint256 gain = 0;
        uint256 loss = 0;

        if (nowStrategyTotalDebt > lastStrategyTotalDebt) {
            gain = nowStrategyTotalDebt - lastStrategyTotalDebt;
        } else if (nowStrategyTotalDebt < lastStrategyTotalDebt) {
            loss = lastStrategyTotalDebt - nowStrategyTotalDebt;
        }

        if (strategyParam.enforceChangeLimit) {
            if (gain > 0) {
                require(
                    gain <=
                        ((lastStrategyTotalDebt *
                            strategyParam.profitLimitRatio) / MAX_BPS),
                    "GL"
                );
            } else if (loss > 0) {
                require(
                    loss <=
                        ((lastStrategyTotalDebt *
                            strategyParam.lossLimitRatio) / MAX_BPS),
                    "LL"
                );
            }
        } else {
            strategies[_strategy].enforceChangeLimit = true;
            // The check is turned off only once and turned back on.
        }

        strategies[_strategy].totalDebt = nowStrategyTotalDebt;
        totalDebt =
            totalDebt +
            nowStrategyTotalDebt +
            lendValue -
            lastStrategyTotalDebt;

        strategies[_strategy].lastReport = block.timestamp;
        //        lastReport = block.timestamp;

        emit StrategyReported(
            _strategy,
            gain,
            loss,
            lastStrategyTotalDebt,
            nowStrategyTotalDebt,
            _rewardTokens,
            _claimAmounts
        );
    }

    function report(
        address[] memory _rewardTokens,
        uint256[] memory _claimAmounts
    ) external isActiveStrategy(msg.sender) nonReentrant {
        _report(msg.sender, _rewardTokens, _claimAmounts, 0);
    }

    function balanceOfToken(address tokenAddress, address owner)
        internal
        view
        returns (uint256)
    {
        return IERC20Upgradeable(tokenAddress).balanceOf(owner);
    }

    /***************************************
                   Pricing
    ****************************************/

    /**
     * @dev Returns the total price in 18 digit USD for a given asset.
     *      Never goes above 1, since that is how we price mints
     * @param asset address of the asset
     * @return uint256 USD price of 1 of the asset, in 18 decimal fixed
     */
    function _priceUSDMint(address asset) internal view returns (uint256) {
        uint256 price = IValueInterpreter(valueInterpreter).price(asset);
        if (price > 1e18) {
            price = 1e18;
        }
        return price;
    }

    /**
     * @dev Returns the total price in 18 digit USD for a given asset.
     *      Never goes below 1, since that is how we price redeems
     * @param asset Address of the asset
     * @return price USD price of 1 of the asset, in 18 decimal fixed
     * @return redeemPrice USD redeem price of 1 of the asset, in 18 decimal fixed
     */
    function priceUSDRedeem(address asset)
        internal
        view
        returns (uint256 price, uint256 redeemPrice)
    {
        price = IValueInterpreter(valueInterpreter).price(asset);
        redeemPrice = priceInRedeem(price);
    }

    /**
     * @dev Returns the total price in 18 digit USD for a given price.
     *      Never goes below 1, since that is how we price redeems
     * @param price oracle price of the asset
     * @return uint256 USD price of 1 of the asset, in 18 decimal fixed
     */
    function priceInRedeem(uint256 price) internal view returns (uint256) {
        if (price < 1e18) {
            return 1e18;
        }
        return price;
    }

    /**
     * @dev Falldown to the admin implementation
     * @notice This is a catch all for all functions not declared in core
     */
    fallback() external payable {
        bytes32 slot = adminImplPosition;

        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(
                gas(),
                sload(slot),
                0,
                calldatasize(),
                0,
                0
            )

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
