// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../library/StableMath.sol";

import "./VaultStorage.sol";
import "../exchanges/IExchangeAggregator.sol";

/// @title Vault
/// @notice Vault is the core of the BoC protocol
/// @notice Vault stores and manages collateral funds of all positions
/// @author Bank of Chain Protocol Inc
contract Vault is VaultStorage {
    using StableMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using IterableIntMap for IterableIntMap.AddressToIntMap;

    address private constant W_ETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function initialize(
        address _accessControlProxy,
        address _treasury,
        address _exchangeManager,
        address _valueInterpreter,
        uint256 _valueType
    ) public initializer {
        _initAccessControl(_accessControlProxy);

        treasury = _treasury;
        exchangeManager = _exchangeManager;
        valueInterpreter = _valueInterpreter;
        vaultType = _valueType;

        rebasePaused = false;

        // 1 / 1000e4
        rebaseThreshold = 1;
        // one week
        maxTimestampBetweenTwoReported = 604800;
        underlyingUnitsPerShare = 1e18;
        //ETHi
        if (_valueType > 0) {
            minCheckedStrategyTotalDebt = 1e17;
        } else {
            minCheckedStrategyTotalDebt = 1000e18;
        }
    }

    modifier whenNotEmergency() {
        require(!emergencyShutdown, "ES"); //emergency shutdown
        _;
    }

    modifier whenNotAdjustPosition() {
        require(!adjustPositionPeriod, "AD"); //AdjustPosition
        _;
    }

    /// @dev Verifies that the rebasing is not paused.
    modifier whenNotRebasePaused() {
        require(!rebasePaused, "RP"); //Rebase Paused
        _;
    }

    modifier isActiveStrategy(address _strategy) {
        checkActiveStrategy(_strategy);
        _;
    }

    /// @notice Version of vault
    function getVersion() external pure returns (string memory) {
        return "2.0.0";
    }

    /// @notice Minting USDi/ETHi supported assets
    function getSupportAssets() external view returns (address[] memory) {
        return assetSet.values();
    }

    /// @notice Return all strategies
    function getStrategies() external view returns (address[] memory) {
        return strategySet.values();
    }

    /// @notice Assets held by Vault
    function getTrackedAssets() external view returns (address[] memory) {
        return _getTrackedAssets();
    }

    /// @notice Check '_asset' is supported or not
    function checkIsSupportAsset(address _asset) public view {
        require(assetSet.contains(_asset), "NS"); //not support
    }

    /// @notice Vault holds asset value directly in USD(USDi)/ETH(ETHi)(1e18)
    function valueOfTrackedTokens() external view returns (uint256) {
        return _totalAssetInVault();
    }

    /// @notice Vault and vault buffer holds asset value directly USD(USDi)/ETH(ETHi)(1e18)
    function valueOfTrackedTokensIncludeVaultBuffer() external view returns (uint256) {
        return _totalAssetInVaultAndVaultBuffer();
    }

    /// @notice Vault total asset in USD(USDi)/ETH(ETHi)(1e18)
    function totalAssets() external view returns (uint256) {
        return _totalAssetInVault() + totalDebt;
    }

    /// @notice Vault and vault buffer total asset in USD(USDi)/ETH(ETHi)(1e18)
    function totalAssetsIncludeVaultBuffer() external view returns (uint256) {
        return _totalAssetInVaultAndVaultBuffer() + totalDebt;
    }

    /// @notice Vault total value(by oracle price) in USD(1e18)
    function totalValue() external view returns (uint256) {
        return totalValueInVault() + totalValueInStrategies();
    }

    /// @dev Calculate total value of all assets held in Vault.
    /// @return _value Total value(by oracle price) in USD (1e18)
    function totalValueInVault() public view returns (uint256 _value) {
        address[] memory _trackedAssets = _getTrackedAssets();
        for (uint256 i = 0; i < _trackedAssets.length; i++) {
            address _trackedAsset = _trackedAssets[i];
            uint256 _balance = _balanceOfToken(_trackedAsset, address(this));
            if (_balance > 0) {
                if (NativeToken.NATIVE_TOKEN == _trackedAsset) {
                    _value =
                        _value +
                        IValueInterpreter(valueInterpreter).calcCanonicalAssetValueInUsd(W_ETH, _balance);
                } else {
                    _value =
                        _value +
                        IValueInterpreter(valueInterpreter).calcCanonicalAssetValueInUsd(
                            _trackedAsset,
                            _balance
                        );
                }
            }
        }
    }

    /// @dev Calculate total value of all assets held in Strategies.
    /// @return _value Total value(by oracle price) in USD (1e18)
    function totalValueInStrategies() public view returns (uint256 _value) {
        uint256 _strategyLength = strategySet.length();
        for (uint256 i = 0; i < _strategyLength; i++) {
            uint256 estimatedTotalAssets = IStrategy(strategySet.at(i)).estimatedTotalAssets();
            if (estimatedTotalAssets > 0) {
                _value = _value + estimatedTotalAssets;
            }
        }
        //ETHi
        if (vaultType > 0) {
            _value = IValueInterpreter(valueInterpreter).calcCanonicalAssetValueInUsd(W_ETH, _value);
        }
    }

    /// @notice Get pegToken price in USD(USDi)/ETH(ETHi)(1e18)
    /// @return  price in USD(USDi)/ETH(ETHi)(1e18)
    function getPegTokenPrice() external view returns (uint256) {
        uint256 _totalSupply = IPegToken(pegTokenAddress).totalSupply();
        uint256 _pegTokenPrice = 1e18;
        if (_totalSupply > 0) {
            address[] memory _trackedAssets = _getTrackedAssets();
            uint256 _trackedAssetsLength = _trackedAssets.length;
            uint256[] memory _assetPrices = new uint256[](_trackedAssetsLength);
            uint256[] memory _assetDecimals = new uint256[](_trackedAssetsLength);
            uint256 _totalAssetInVault;
            uint256 _totalTransferValue;
            for (uint256 i = 0; i < _trackedAssetsLength; i++) {
                address _trackedAsset = _trackedAssets[i];
                uint256 _balance = _balanceOfToken(_trackedAsset, address(this));
                if (_balance > 0) {
                    _totalAssetInVault =
                        _totalAssetInVault +
                        _calculateAssetValue(_assetPrices, _assetDecimals, i, _trackedAsset, _balance);
                }
                _balance = transferFromVaultBufferAssetsMap[_trackedAsset];
                if (_balance > 0) {
                    _totalTransferValue =
                        _totalTransferValue +
                        _calculateAssetValue(_assetPrices, _assetDecimals, i, _trackedAsset, _balance);
                }
            }
            _pegTokenPrice =
                ((_totalAssetInVault + totalDebt - _totalTransferValue) * 1e18) /
                _totalSupply;
        }
        return _pegTokenPrice;
    }

    /// @notice Check '_strategy' is active or not
    function checkActiveStrategy(address _strategy) public view {
        require(strategySet.contains(_strategy), "NE"); //not exist
    }

    /// @notice Estimate the pending share amount that can be minted
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @dev Support single asset or multi-assets
    /// @return The share Amount estimated
    function estimateMint(address[] memory _assets, uint256[] memory _amounts)
        public
        view
        returns (uint256)
    {
        (uint256 _mintAmount, ) = _estimateMint(_assets, _amounts);
        return _mintAmount;
    }

    /// @notice Minting the USDi/ETHi ticket with stablecoins(USDi)/ETH(ETHi)
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @dev Support single asset or multi-assets
    /// @return The amount of share minted
    function mint(
        address[] memory _assets,
        uint256[] memory _amounts,
        uint256 _minimumAmount
    ) external payable whenNotEmergency whenNotAdjustPosition nonReentrant returns (uint256) {
        (uint256 _shareAmount, uint256 _ethAmount) = _estimateMint(_assets, _amounts);
        require(_ethAmount == msg.value, "AI"); //amount invalid
        if (_minimumAmount > 0) {
            require(_shareAmount >= _minimumAmount, "RLTM"); //received less than the minimum
        }

        for (uint256 i = 0; i < _assets.length; i++) {
            address _asset = _assets[i];
            if (_asset != NativeToken.NATIVE_TOKEN) {
                // Transfer the deposited coins to the vault
                IERC20Upgradeable(_asset).safeTransferFrom(msg.sender, vaultBufferAddress, _amounts[i]);
            }
        }
        IVaultBuffer(vaultBufferAddress).mint{value: _ethAmount}(msg.sender, _shareAmount);

        emit Mint(msg.sender, _assets, _amounts, _shareAmount);
        return _shareAmount;
    }

    /// @notice Burn USDi/ETHi,return stablecoins(USDi)/xETH(ETHi)
    /// @param _amount Amount of USDi to burn
    /// @param _minimumAmount Minimum usd to receive in return
    /// @param _redeemFeeBps Redemption fee in basis points
    /// @param _trusteeFeeBps Amount of yield collected in basis points
    /// @return _assets The address list of assets to receive
    /// @return _amounts The amount list of assets to receive
    function burn(
        uint256 _amount,
        uint256 _minimumAmount,
        uint256 _redeemFeeBps,
        uint256 _trusteeFeeBps
    )
        external
        whenNotEmergency
        whenNotAdjustPosition
        nonReentrant
        returns (address[] memory _assets, uint256[] memory _amounts)
    {
        uint256 _accountBalance = IPegToken(pegTokenAddress).balanceOf(msg.sender);
        require(_amount > 0 && _amount <= _accountBalance, "AI"); //USDi not enough,amount is invalid
        require(_redeemFeeBps == redeemFeeBps, "RI"); //redeemFeeBps invalid
        require(_trusteeFeeBps == trusteeFeeBps, "TI"); //trusteeFeeBps invalid

        address[] memory _trackedAssets = _getTrackedAssets();
        uint256[] memory _assetPrices = new uint256[](_trackedAssets.length);
        uint256[] memory _assetDecimals = new uint256[](_trackedAssets.length);
        (uint256 _sharesAmount, uint256 _actualAsset) = _repayToVault(
            _amount,
            _accountBalance,
            _redeemFeeBps,
            _trackedAssets,
            _assetPrices,
            _assetDecimals
        );

        uint256 _actuallyReceivedAmount;
        (_assets, _amounts, _actuallyReceivedAmount) = _calculateAndTransfer(
            _actualAsset,
            _trackedAssets,
            _assetPrices,
            _assetDecimals
        );

        if (_minimumAmount > 0) {
            require(_actuallyReceivedAmount >= _minimumAmount, "RLTM"); //received less than minimum
        }
        _burnRebaseAndEmit(
            _amount,
            _actuallyReceivedAmount,
            _sharesAmount,
            _trusteeFeeBps,
            _assets,
            _amounts,
            _trackedAssets,
            _assetPrices,
            _assetDecimals
        );
    }

    /// @notice Redeem the funds from specified strategy.
    /// @param  _strategy The specified strategy to redeem
    /// @param _amount The amount to redeem in USD
    /// @param _outputCode The code of output
    function redeem(
        address _strategy,
        uint256 _amount,
        uint256 _outputCode
    ) external isKeeperOrVaultOrGovOrDelegate isActiveStrategy(_strategy) nonReentrant {
        uint256 _strategyAssetValue = strategies[_strategy].totalDebt;
        require(_amount <= _strategyAssetValue, "AI"); //amount invalid

        (address[] memory _assets, uint256[] memory _amounts) = IStrategy(_strategy).repay(
            _amount,
            _strategyAssetValue,
            _outputCode
        );
        if (adjustPositionPeriod) {
            uint256 _assetsLength = _assets.length;
            for (uint256 i = 0; i < _assetsLength; i++) {
                uint256 _amount = _amounts[i];
                if (_amount > 0) {
                    redeemAssetsMap[_assets[i]] += _amount;
                }
            }
        }
        uint256 _nowStrategyTotalDebt = strategies[_strategy].totalDebt;
        uint256 _thisWithdrawValue = (_nowStrategyTotalDebt * _amount) / _strategyAssetValue;
        strategies[_strategy].totalDebt = _nowStrategyTotalDebt - _thisWithdrawValue;
        totalDebt -= _thisWithdrawValue;
        emit Redeem(_strategy, _amount, _assets, _amounts);
    }

    /// @notice Allocate funds in Vault to strategies.
    /// @param  _strategy The specified strategy to lend
    /// @param _tokens The address list of token wanted
    /// @param _amounts The amount list of token wanted
    function lend(
        address _strategy,
        address[] memory _tokens,
        uint256[] memory _amounts
    ) external isKeeperOrVaultOrGovOrDelegate whenNotEmergency isActiveStrategy(_strategy) nonReentrant {
        address _strategyAddress = _strategy;
        uint256[] memory _amountsLocal = _amounts;
        (address[] memory _wants, uint256[] memory _ratios) = IStrategy(_strategyAddress).getWantsInfo();
        uint256 _wantsLength = _wants.length;
        require(_amountsLocal.length == _wantsLength, "ASI"); //_amounts invalid
        require(_tokens.length == _wantsLength, "TSI"); //_tokens invalid
        {
            for (uint256 i = 0; i < _wantsLength; i++) {
                require(_tokens[i] == _wants[i], "TSI"); //tokens invalid
            }
        }
        //Definition rule 0 means unconstrained, currencies that do not participate are not in the returned wants
        uint256 _minProductIndex;
        bool _isWantRatioIgnorable = IStrategy(_strategyAddress).isWantRatioIgnorable();
        if (!_isWantRatioIgnorable && _wantsLength > 1) {
            for (uint256 i = 1; i < _wantsLength; i++) {
                if (_ratios[i] == 0) {
                    continue;
                } else if (_ratios[_minProductIndex] == 0) {
                    //minProductIndex is assigned to the first index whose proportion is not 0
                    _minProductIndex = i;
                } else if (
                    _amountsLocal[_minProductIndex] * _ratios[i] >
                    _amountsLocal[i] * _ratios[_minProductIndex]
                ) {
                    _minProductIndex = i;
                }
            }
        }

        uint256 _lendValue;
        uint256 _ethAmount;
        {
            uint256 _vaultType = vaultType;
            uint256 _minAmount = _amountsLocal[_minProductIndex];
            uint256 _minAspect = _ratios[_minProductIndex];
            for (uint256 i = 0; i < _wantsLength; i++) {
                uint256 _actualAmount = _amountsLocal[i];
                if (_actualAmount > 0) {
                    address _want = _wants[i];
                    if (!_isWantRatioIgnorable){
                        if (_ratios[i] > 0) {
                            _actualAmount = (_ratios[i] * _minAmount) / _minAspect;
                            _amountsLocal[i] = _actualAmount;
                        }else{
                            _amountsLocal[i] = 0;
                            continue;
                        }
                    }
                    if (_want == NativeToken.NATIVE_TOKEN) {
                        _lendValue += _actualAmount;
                        _ethAmount = _actualAmount;
                    } else {
                        if (_vaultType > 0) {
                            _lendValue =
                                _lendValue +
                                IValueInterpreter(valueInterpreter).calcCanonicalAssetValueInEth(
                                    _want,
                                    _actualAmount
                                );
                        } else {
                            _lendValue =
                                _lendValue +
                                IValueInterpreter(valueInterpreter).calcCanonicalAssetValueInUsd(
                                    _want,
                                    _actualAmount
                                );
                        }
                        IERC20Upgradeable(_want).safeTransfer(_strategyAddress, _actualAmount);
                    }
                }
            }
        }
        {
            IStrategy(_strategyAddress).borrow{value: _ethAmount}(_wants, _amountsLocal);
            address[] memory _rewardTokens;
            uint256[] memory _claimAmounts;
            _report(_strategyAddress, _rewardTokens, _claimAmounts, _lendValue, 1);
        }
        emit LendToStrategy(_strategyAddress, _wants, _amountsLocal, _lendValue);
    }

    function exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory _exchangeParam
    ) external isKeeperOrVaultOrGovOrDelegate nonReentrant returns (uint256) {
        return _exchange(_fromToken, _toToken, _amount, _exchangeParam);
    }

    /// @notice Change USDi/ETHi supply with Vault total assets.
    /// @param _trusteeFeeBps Amount of yield collected in basis points
    function rebase(uint256 _trusteeFeeBps)
        external
        whenNotEmergency
        whenNotAdjustPosition
        whenNotRebasePaused
        nonReentrant
    {
        require(_trusteeFeeBps == trusteeFeeBps, "TI"); //trusteeFeeBps invalid
        uint256 _totalAssets = _totalAssetInVault() + totalDebt;
        _rebase(_totalAssets, _trusteeFeeBps);
    }

    /// @dev Report the current asset of strategy caller
    /// @param _strategies The address list of strategies to report
    /// Requirement: only keeper call
    /// Emits a {StrategyReported} event.
    function reportByKeeper(address[] memory _strategies) external isKeeperOrVaultOrGovOrDelegate {
        address[] memory _rewardTokens;
        uint256[] memory _claimAmounts;
        uint256 _strategiesLength = _strategies.length;
        for (uint256 i = 0; i < _strategiesLength; i++) {
            _report(_strategies[i], _rewardTokens, _claimAmounts, 0, 2);
        }
    }

    /// @dev Report the current asset of strategy caller
    /// Requirement: only the strategy caller is active
    /// Emits a {StrategyReported} event.
    function reportWithoutClaim() external isActiveStrategy(msg.sender) {
        address[] memory _rewardTokens;
        uint256[] memory _claimAmounts;
        _report(msg.sender, _rewardTokens, _claimAmounts, 0, 2);
    }

    /// @dev Report the current asset of strategy caller
    /// @param _rewardTokens The reward token list
    /// @param _claimAmounts The claim amount list
    /// Requirement: only the strategy caller is active
    /// Emits a {StrategyReported} event.
    function report(address[] memory _rewardTokens, uint256[] memory _claimAmounts)
        external
        isActiveStrategy(msg.sender)
    {
        _report(msg.sender, _rewardTokens, _claimAmounts, 0, 0);
    }

    /// @notice start  Adjust  Position
    function startAdjustPosition()
        external
        isKeeperOrVaultOrGovOrDelegate
        whenNotAdjustPosition
        whenNotEmergency
        nonReentrant
    {
        adjustPositionPeriod = true;
        address[] memory _trackedAssets = _getTrackedAssets();

        (
            uint256[] memory _vaultAmounts,
            uint256[] memory _transferAmounts,
            bool _vaultBufferAboveZero
        ) = _calculateVault(_trackedAssets, true);
        uint256 _totalDebt = totalDebt;
        if (_vaultBufferAboveZero) {
            uint256 _trackedAssetsLength = _trackedAssets.length;
            uint256[] memory _assetPrices = new uint256[](_trackedAssetsLength);
            uint256[] memory _assetDecimals = new uint256[](_trackedAssetsLength);
            uint256 _totalAssetInVault;
            for (uint256 i = 0; i < _trackedAssetsLength; i++) {
                address _trackedAsset = _trackedAssets[i];
                uint256 _amount = _vaultAmounts[i];
                if (_amount > 0) {
                    _totalAssetInVault =
                        _totalAssetInVault +
                        _calculateAssetValue(_assetPrices, _assetDecimals, i, _trackedAsset, _amount);
                }
            }
            uint256 _totalAssets = _totalAssetInVault + _totalDebt;
            uint256 _totalShares = IPegToken(pegTokenAddress).totalShares();
            if (!rebasePaused) {
                _rebase(_totalAssets, _totalShares, trusteeFeeBps);
            }
            IVaultBuffer(vaultBufferAddress).transferCashToVault(_trackedAssets, _transferAmounts);
        }
        uint256 _totalDebtOfBeforeAdjustPosition = _totalDebt;
        totalDebtOfBeforeAdjustPosition = _totalDebtOfBeforeAdjustPosition;
        emit StartAdjustPosition(
            _totalDebtOfBeforeAdjustPosition,
            _trackedAssets,
            _vaultAmounts,
            _transferAmounts
        );
    }

    /// @notice end  Adjust Position
    function endAdjustPosition() external isKeeperOrVaultOrGovOrDelegate nonReentrant {
        require(adjustPositionPeriod, "ADO"); //AdjustPosition overed
        address[] memory _trackedAssets = _getTrackedAssets();
        uint256 _trackedAssetsLength = _trackedAssets.length;
        uint256[] memory _assetPrices = new uint256[](_trackedAssetsLength);
        uint256[] memory _assetDecimals = new uint256[](_trackedAssetsLength);

        (uint256[] memory _vaultAmounts, , ) = _calculateVault(_trackedAssets, false);

        uint256 _transferValue;
        uint256 _redeemValue;
        uint256 _vaultValueOfNow;
        uint256 _vaultValueOfBefore;
        for (uint256 i = 0; i < _trackedAssetsLength; i++) {
            address _trackedAsset = _trackedAssets[i];
            _transferValue =
                _transferValue +
                _calculateAssetValue(
                    _assetPrices,
                    _assetDecimals,
                    i,
                    _trackedAsset,
                    transferFromVaultBufferAssetsMap[_trackedAsset]
                );
            _redeemValue =
                _redeemValue +
                _calculateAssetValue(
                    _assetPrices,
                    _assetDecimals,
                    i,
                    _trackedAsset,
                    redeemAssetsMap[_trackedAsset]
                );
            _vaultValueOfNow =
                _vaultValueOfNow +
                _calculateAssetValue(_assetPrices, _assetDecimals, i, _trackedAsset, _vaultAmounts[i]);
            _vaultValueOfBefore =
                _vaultValueOfBefore +
                _calculateAssetValue(
                    _assetPrices,
                    _assetDecimals,
                    i,
                    _trackedAsset,
                    beforeAdjustPositionAssetsMap[_trackedAsset]
                );
        }

        uint256 _totalDebtOfBefore = totalDebtOfBeforeAdjustPosition;
        uint256 _totalDebtOfNow = totalDebt;

        uint256 _totalValueOfNow = _totalDebtOfNow + _vaultValueOfNow;
        uint256 _totalValueOfBefore = _totalDebtOfBefore + _vaultValueOfBefore;

        {
            uint256 _transferAssets;
            uint256 _old2LendAssets;
            if (_vaultValueOfNow + _transferValue < _vaultValueOfBefore) {
                _old2LendAssets = _vaultValueOfBefore - _vaultValueOfNow - _transferValue;
            }
            if (_redeemValue + _old2LendAssets > _totalValueOfBefore - _transferValue) {
                _redeemValue = _totalValueOfBefore - _transferValue - _old2LendAssets;
            }
            if (_totalValueOfNow > _totalValueOfBefore) {
                uint256 _gain = _totalValueOfNow - _totalValueOfBefore;
                if (_transferValue > 0) {
                    _transferAssets =
                        _transferValue +
                        (_gain * _transferValue) /
                        (_transferValue + _redeemValue + _old2LendAssets);
                }
            } else {
                uint256 _loss = _totalValueOfBefore - _totalValueOfNow;
                if (_transferValue > 0) {
                    _transferAssets =
                        _transferValue -
                        (_loss * _transferValue) /
                        (_transferValue + _redeemValue + _old2LendAssets);
                }
            }
            uint256 _totalShares = IPegToken(pegTokenAddress).totalShares();
            if (!rebasePaused && _totalShares > 0) {
                _totalShares = _rebase(_totalValueOfNow - _transferAssets, _totalShares, trusteeFeeBps);
            }
            if (_transferAssets > 0) {
                uint256 _sharesAmount = _calculateShare(
                    _transferAssets,
                    _totalValueOfNow - _transferAssets,
                    _totalShares
                );
                if (_sharesAmount > 0) {
                    IPegToken(pegTokenAddress).mintShares(vaultBufferAddress, _sharesAmount);
                }
            }
        }

        {
            totalDebtOfBeforeAdjustPosition = 0;
            for (uint256 i = 0; i < _trackedAssetsLength; i++) {
                address _trackedAsset = _trackedAssets[i];
                redeemAssetsMap[_trackedAsset] = 0;
                beforeAdjustPositionAssetsMap[_trackedAsset] = 0;
                transferFromVaultBufferAssetsMap[_trackedAsset] = 0;
            }
            if (!IVaultBuffer(vaultBufferAddress).isDistributing()) {
                IVaultBuffer(vaultBufferAddress).openDistribute();
            }
            adjustPositionPeriod = false;
        }

        emit EndAdjustPosition(
            _transferValue,
            _redeemValue,
            _totalDebtOfNow,
            _totalValueOfNow,
            _totalValueOfBefore
        );
    }

    function _calculateVault(address[] memory _trackedAssets, bool _dealVaultBuffer)
        internal
        returns (
            uint256[] memory,
            uint256[] memory,
            bool
        )
    {
        uint256 _trackedAssetsLength = _trackedAssets.length;
        uint256[] memory _transferAmounts = new uint256[](_trackedAssetsLength);
        uint256[] memory _vaultAmounts = new uint256[](_trackedAssetsLength);
        bool _vaultBufferAboveZero = false;
        for (uint256 i = 0; i < _trackedAssetsLength; i++) {
            address _trackedAsset = _trackedAssets[i];
            uint256 _balance;
            if (_dealVaultBuffer && assetSet.contains(_trackedAsset)) {
                _balance = _balanceOfToken(_trackedAsset, vaultBufferAddress);
                if (_balance > 0) {
                    _transferAmounts[i] = _balance;
                    _vaultBufferAboveZero = true;
                    transferFromVaultBufferAssetsMap[_trackedAsset] = _balance;
                }
            }
            uint256 _vaultAmount = _balanceOfToken(_trackedAsset, address(this));
            if (_vaultAmount > 0) {
                _vaultAmounts[i] = _vaultAmount;
            }
            if (_dealVaultBuffer && _vaultAmount + _balance > 0) {
                beforeAdjustPositionAssetsMap[_trackedAsset] = _vaultAmount + _balance;
            }
        }
        return (_vaultAmounts, _transferAmounts, _vaultBufferAboveZero);
    }

    /// @notice Assets held by Vault
    function _getTrackedAssets() internal view returns (address[] memory) {
        return trackedAssetsMap._inner._keys.values();
    }

    /// @dev Internal to calculate total value of all assets held in Vault.
    /// @return Total value in USD(USDi)/ETH(ETHi) (1e18)
    function _totalAssetInVault() internal view returns (uint256) {
        address[] memory _trackedAssets = _getTrackedAssets();
        uint256 _trackedAssetsLength = _trackedAssets.length;
        uint256[] memory _assetPrices = new uint256[](_trackedAssetsLength);
        uint256[] memory _assetDecimals = new uint256[](_trackedAssetsLength);
        return _totalAssetInVault(_trackedAssets, _assetPrices, _assetDecimals);
    }

    /// @dev Internal to calculate total value of all assets held in Vault.
    /// @return Total value in USD(USDi)/ETH(ETHi) (1e18)
    function _totalAssetInVault(
        address[] memory _trackedAssets,
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals
    ) internal view returns (uint256) {
        uint256 _totalAssetInVaultLocal;
        uint256 _trackedAssetsLength = _trackedAssets.length;
        for (uint256 i = 0; i < _trackedAssetsLength; i++) {
            address _trackedAsset = _trackedAssets[i];
            uint256 _balance = _balanceOfToken(_trackedAsset, address(this));
            if (_balance > 0) {
                _totalAssetInVaultLocal =
                    _totalAssetInVaultLocal +
                    _calculateAssetValue(_assetPrices, _assetDecimals, i, _trackedAsset, _balance);
            }
        }
        return _totalAssetInVaultLocal;
    }

    function _totalAssetInVaultAndVaultBuffer() internal view returns (uint256) {
        address[] memory _trackedAssets = _getTrackedAssets();
        uint256 _trackedAssetsLength = _trackedAssets.length;
        uint256[] memory _assetPrices = new uint256[](_trackedAssetsLength);
        uint256[] memory _assetDecimals = new uint256[](_trackedAssetsLength);

        uint256 _totalAssetInVaultAndVaultBuffer;
        for (uint256 i = 0; i < _trackedAssetsLength; i++) {
            address _trackedAsset = _trackedAssets[i];
            uint256 _assetBalancesInVault = _balanceOfToken(_trackedAsset, address(this));
            uint256 _assetBalancesInVaultBuffer = _balanceOfToken(_trackedAsset, vaultBufferAddress);
            uint256 _balance = _assetBalancesInVault + _assetBalancesInVaultBuffer;
            if (_balance > 0) {
                _totalAssetInVaultAndVaultBuffer =
                    _totalAssetInVaultAndVaultBuffer +
                    _calculateAssetValue(_assetPrices, _assetDecimals, i, _trackedAsset, _balance);
            }
        }
        return _totalAssetInVaultAndVaultBuffer;
    }

    function _estimateMint(address[] memory _assets, uint256[] memory _amounts)
        private
        view
        returns (uint256 _mintAmount, uint256 _ethAmount)
    {
        _ethAmount = _checkMintAssets(_assets, _amounts);
        for (uint256 i = 0; i < _assets.length; i++) {
            address _asset = _assets[i];
            uint256 _assetPrice = _getAssetPrice(_asset);
            uint256 _assetDecimal = trackedAssetDecimalsMap[_asset];
            _mintAmount += _amounts[i].mulTruncateScale(_assetPrice, 10**_assetDecimal);
        }
        uint256 _minimumInvestmentAmount = minimumInvestmentAmount;
        if (_minimumInvestmentAmount > 0) {
            require(_mintAmount >= _minimumInvestmentAmount, "ILTM"); //Investment less than minimum
        }
    }

    /// @notice withdraw from strategy queue
    function _repayFromWithdrawQueue(uint256 _needWithdrawValue) internal {
        uint256 _totalWithdrawValue;
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            address _strategy = withdrawQueue[i];
            if (_strategy == ZERO_ADDRESS) break;

            uint256 _strategyTotalValue = strategies[_strategy].totalDebt;
            if (_strategyTotalValue <= 0) {
                continue;
            }

            uint256 _strategyWithdrawValue;
            if (_needWithdrawValue > _strategyTotalValue) {
                _strategyWithdrawValue = _strategyTotalValue;
                _needWithdrawValue -= _strategyWithdrawValue;
            } else {
                //If there is less than 1U/0.001ETH left, then all redemption
                uint256 _leftMinValue = vaultType > 0 ? 1e18 : 1e15;
                if (_needWithdrawValue + _leftMinValue >= _strategyTotalValue) {
                    _strategyWithdrawValue = _strategyTotalValue;
                } else {
                    _strategyWithdrawValue = _needWithdrawValue;
                }
                _needWithdrawValue = 0;
            }

            (address[] memory _assets, uint256[] memory _amounts) = IStrategy(_strategy).repay(
                _strategyWithdrawValue,
                _strategyTotalValue,
                0
            );
            emit RepayFromStrategy(
                _strategy,
                _strategyWithdrawValue,
                _strategyTotalValue,
                _assets,
                _amounts
            );
            uint256 _nowStrategyTotalDebt = strategies[_strategy].totalDebt;
            uint256 _thisWithdrawValue = (_nowStrategyTotalDebt * _strategyWithdrawValue) /
                _strategyTotalValue;
            strategies[_strategy].totalDebt = _nowStrategyTotalDebt - _thisWithdrawValue;
            _totalWithdrawValue += _thisWithdrawValue;

            if (_needWithdrawValue <= 0) {
                break;
            }
        }
        totalDebt -= _totalWithdrawValue;
    }

    /// @notice withdraw from vault buffer
    function _repayFromVaultBuffer(
        uint256 _needTransferValue,
        address[] memory _trackedAssets,
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals,
        uint256 _totalAssets,
        uint256 _totalShares
    ) internal returns (uint256) {
        address[] memory _transferAssets = _trackedAssets;
        uint256 _transferAssetsLength = _transferAssets.length;
        uint256[] memory _amounts = new uint256[](_transferAssetsLength);
        uint256 _totalTransferValue;
        //price in vault
        for (uint256 i = 0; i < _transferAssetsLength; i++) {
            address _trackedAsset = _transferAssets[i];
            if (assetSet.contains(_trackedAsset)) {
                uint256 _assetBalancesInVaultBuffer = _balanceOfToken(_trackedAsset, vaultBufferAddress);
                if (_assetBalancesInVaultBuffer > 0) {
                    uint256 _value = _calculateAssetValue(
                        _assetPrices,
                        _assetDecimals,
                        i,
                        _trackedAsset,
                        _assetBalancesInVaultBuffer
                    );

                    if (_needTransferValue > _value) {
                        _totalTransferValue = _totalTransferValue + _value;
                        _needTransferValue = _needTransferValue - _value;
                        _amounts[i] = _assetBalancesInVaultBuffer;
                    } else {
                        _totalTransferValue = _totalTransferValue + _needTransferValue;
                        _amounts[i] = (_assetBalancesInVaultBuffer * _needTransferValue) / _value;
                        _needTransferValue = 0;
                        break;
                    }
                }
            }
        }
        if (_totalTransferValue > 0) {
            IVaultBuffer(vaultBufferAddress).transferCashToVault(_transferAssets, _amounts);

            uint256 _totalTransferShares = _calculateShare(
                _totalTransferValue,
                _totalAssets,
                _totalShares
            );
            IPegToken(pegTokenAddress).mintShares(vaultBufferAddress, _totalTransferShares);

            emit PegTokenSwapCash(_totalTransferValue, _transferAssets, _amounts);
        }
        return _totalTransferValue;
    }

    function _calculateShare(
        uint256 _amount,
        uint256 _totalAssets,
        uint256 _totalShares
    ) internal view returns (uint256) {
        uint256 _shareAmount;
        if (_totalAssets > 0 && _totalShares > 0) {
            _shareAmount = (_amount * _totalShares) / _totalAssets;
        }
        if (_shareAmount == 0) {
            uint256 _underlyingUnitsPerShare = underlyingUnitsPerShare;
            if (_underlyingUnitsPerShare > 0) {
                _shareAmount = _amount.divPreciselyScale(_underlyingUnitsPerShare, 1e27);
            } else {
                _shareAmount = _amount * 1e9;
            }
        }
        return _shareAmount;
    }

    /// @notice calculate need transfer amount from vault ,set to outputs
    function _calculateOutputs(
        uint256 _needTransferAmount,
        address[] memory _trackedAssets,
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals
    ) internal view returns (uint256[] memory) {
        uint256 _trackedAssetsLength = _trackedAssets.length;
        uint256[] memory _outputs = new uint256[](_trackedAssetsLength);

        for (uint256 i = 0; i < _trackedAssetsLength; i++) {
            address _trackedAsset = _trackedAssets[i];
            uint256 _balance = _balanceOfToken(_trackedAsset, address(this));
            if (_balance > 0) {
                uint256 _value = _calculateAssetValue(
                    _assetPrices,
                    _assetDecimals,
                    i,
                    _trackedAsset,
                    _balance
                );

                if (_value >= _needTransferAmount) {
                    _outputs[i] = (_balance * _needTransferAmount) / _value;
                    break;
                } else {
                    _outputs[i] = _balance;
                    _needTransferAmount = _needTransferAmount - _value;
                }
            }
        }
        return _outputs;
    }

    /// @notice calculate Asset value in USD(USDi)/ETH(ETHi) by oracle price
    /// @param _assetPrices array of asset price
    /// @param _assetDecimals array of asset decimal
    /// @param _assetIndex index of the asset in trackedAssets array
    /// @param _trackedAsset address of the asset
    /// @return The share amount
    function _calculateAssetValue(
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals,
        uint256 _assetIndex,
        address _trackedAsset,
        uint256 _balance
    ) private view returns (uint256) {
        uint256 _assetPrice = _getAssetPrice(_assetPrices, _assetIndex, _trackedAsset);
        uint256 _assetDecimal = _getAssetDecimals(_assetDecimals, _assetIndex, _trackedAsset);

        uint256 _value = _balance.mulTruncateScale(_assetPrice, 10**_assetDecimal);
        return _value;
    }

    // @notice without exchange token and transfer form vault to user
    function _transfer(
        uint256[] memory _outputs,
        address[] memory _trackedAssets,
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals
    ) internal returns (uint256) {
        uint256 _actualAmount;
        uint256 _trackedAssetsLength = _trackedAssets.length;
        for (uint256 i = 0; i < _trackedAssetsLength; i++) {
            uint256 _amount = _outputs[i];
            if (_amount > 0) {
                address _trackedAsset = _trackedAssets[i];
                if (_trackedAsset == NativeToken.NATIVE_TOKEN) {
                    _actualAmount = _actualAmount + _amount;
                    payable(msg.sender).transfer(_amount);
                } else {
                    _actualAmount =
                        _actualAmount +
                        _calculateAssetValue(_assetPrices, _assetDecimals, i, _trackedAsset, _amount);
                    IERC20Upgradeable(_trackedAsset).safeTransfer(msg.sender, _amount);
                }
            }
        }
        return _actualAmount;
    }

    function _repayToVault(
        uint256 _amount,
        uint256 _accountBalance,
        uint256 _redeemFeeBps,
        address[] memory _trackedAssets,
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals
    ) internal returns (uint256 _sharesAmount, uint256 _actualAsset) {
        uint256 _totalAssetInVault = _totalAssetInVault(_trackedAssets, _assetPrices, _assetDecimals);
        uint256 _actualAmount = _amount;
        uint256 _currentTotalAssets = _totalAssetInVault + totalDebt;
        uint256 _currentTotalShares = IPegToken(pegTokenAddress).totalShares();
        {
            uint256 _underlyingUnitsPerShare = underlyingUnitsPerShare;
            if (_accountBalance == _actualAmount) {
                _sharesAmount = IPegToken(pegTokenAddress).sharesOf(msg.sender);
            } else {
                _sharesAmount = _actualAmount.divPreciselyScale(_underlyingUnitsPerShare, 1e27);
            }
            // Calculate redeem fee
            if (_redeemFeeBps > 0) {
                _actualAmount = _actualAmount - (_actualAmount * _redeemFeeBps) / MAX_BPS;
            }
            uint256 _currentTotalSupply = _currentTotalShares.mulTruncateScale(
                _underlyingUnitsPerShare,
                1e27
            );
            _actualAsset = (_actualAmount * _currentTotalAssets) / _currentTotalSupply;
        }

        // vault not enough,withdraw from vault buffer
        if (_totalAssetInVault < _actualAsset) {
            _totalAssetInVault =
                _totalAssetInVault +
                _repayFromVaultBuffer(
                    _actualAsset - _totalAssetInVault,
                    _trackedAssets,
                    _assetPrices,
                    _assetDecimals,
                    _currentTotalAssets,
                    _currentTotalShares
                );
        }

        // vault not enough,withdraw from withdraw queue strategy
        if (_totalAssetInVault < _actualAsset) {
            _repayFromWithdrawQueue(_actualAsset - _totalAssetInVault);
        }
    }

    function _calculateAndTransfer(
        uint256 _actualAsset,
        address[] memory _trackedAssets,
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals
    )
        internal
        returns (
            address[] memory,
            uint256[] memory,
            uint256
        )
    {
        // calculate need transfer amount from vault ,set to outputs
        uint256[] memory _outputs = _calculateOutputs(
            _actualAsset,
            _trackedAssets,
            _assetPrices,
            _assetDecimals
        );
        uint256 _actuallyReceivedAmount = _transfer(
            _outputs,
            _trackedAssets,
            _assetPrices,
            _assetDecimals
        );
        return (_trackedAssets, _outputs, _actuallyReceivedAmount);
    }

    // @notice Burn USDi/ETHi and check rebase
    function _burnRebaseAndEmit(
        uint256 _amount,
        uint256 _actualAmount,
        uint256 _shareAmount,
        uint256 _trusteeFeeBps,
        address[] memory _assets,
        uint256[] memory _amounts,
        address[] memory _trackedAssets,
        uint256[] memory _assetPrices,
        uint256[] memory _assetDecimals
    ) internal {
        IPegToken(pegTokenAddress).burnShares(msg.sender, _shareAmount);

        // Until we can prove that we won't affect the prices of our assets
        // by withdrawing them, this should be here.
        // It's possible that a strategy was off on its asset total, perhaps
        // a reward token sold for more or for less than anticipated.
        if (!rebasePaused) {
            uint256 _totalAssetInVault = _totalAssetInVault(_trackedAssets, _assetPrices, _assetDecimals);
            _rebase(_totalAssetInVault + totalDebt, _trusteeFeeBps);
        }
        emit Burn(msg.sender, _amount, _actualAmount, _shareAmount, _assets, _amounts);
    }

    /// @dev Calculate the total value of assets held by the Vault and all
    ///      strategies and update the supply of USDi/ETHi, optionally sending a
    ///      portion of the yield to the trustee.
    function _rebase(uint256 _totalAssets, uint256 _trusteeFeeBps) internal {
        uint256 _totalShares = IPegToken(pegTokenAddress).totalShares();
        _rebase(_totalAssets, _totalShares, _trusteeFeeBps);
    }

    function _rebase(
        uint256 _totalAssets,
        uint256 _totalShares,
        uint256 _trusteeFeeBps
    ) internal returns (uint256) {
        if (_totalShares == 0) {
            return _totalShares;
        }

        uint256 _underlyingUnitsPerShare = underlyingUnitsPerShare;
        uint256 _totalSupply = _totalShares.mulTruncateScale(_underlyingUnitsPerShare, 1e27);

        // Final check should use latest value
        if (
            _totalAssets > _totalSupply &&
            (_totalAssets - _totalSupply) * TEN_MILLION_BPS > _totalSupply * rebaseThreshold
        ) {
            // Yield fee collection
            address _treasuryAddress = treasury;
            if (_trusteeFeeBps > 0 && _treasuryAddress != address(0)) {
                uint256 _yield = _totalAssets - _totalSupply;
                uint256 _fee = (_yield * _trusteeFeeBps) / MAX_BPS;
                require(_yield > _fee, "FMNGTY"); //Fee must not be greater than yield
                if (_fee > 0) {
                    uint256 _sharesAmount = (_fee * _totalShares) / (_totalAssets - _fee);
                    if (_sharesAmount > 0) {
                        IPegToken(pegTokenAddress).mintShares(_treasuryAddress, _sharesAmount);
                        _totalShares = _totalShares + _sharesAmount;
                    }
                }
            }
            uint256 _newUnderlyingUnitsPerShare = _totalAssets.divPreciselyScale(_totalShares, 1e27);
            if (_newUnderlyingUnitsPerShare != _underlyingUnitsPerShare) {
                underlyingUnitsPerShare = _newUnderlyingUnitsPerShare;
                emit Rebase(_totalShares, _totalAssets, _newUnderlyingUnitsPerShare);
            }
        }
        return _totalShares;
    }

    function _exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory _exchangeParam
    ) internal returns (uint256 _exchangeAmount) {
        require(trackedAssetsMap.contains(_toToken), "TTI"); //toToken invalid

        IExchangeAdapter.SwapDescription memory _swapDescription = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _fromToken,
            dstToken: _toToken,
            receiver: address(this)
        });
        if (_fromToken == NativeToken.NATIVE_TOKEN) {
            // payable(exchangeManager).transfer(_amount);
            _exchangeAmount = IExchangeAggregator(exchangeManager).swap{value: _amount}(
                _exchangeParam.platform,
                _exchangeParam.method,
                _exchangeParam.encodeExchangeArgs,
                _swapDescription
            );
        } else {
            IERC20Upgradeable(_fromToken).safeApprove(exchangeManager, 0);
            IERC20Upgradeable(_fromToken).safeApprove(exchangeManager, _amount);
            _exchangeAmount = IExchangeAggregator(exchangeManager).swap(
                _exchangeParam.platform,
                _exchangeParam.method,
                _exchangeParam.encodeExchangeArgs,
                _swapDescription
            );
        }
        uint256 oracleExpectedAmount = IValueInterpreter(valueInterpreter).calcCanonicalAssetValue(
            _fromToken,
            _amount,
            _toToken
        );
        require(
            _exchangeAmount >=
                (oracleExpectedAmount *
                    (MAX_BPS - _exchangeParam.slippage - _exchangeParam.oracleAdditionalSlippage)) /
                    MAX_BPS,
            "OL" //over slip point loss
        );
        emit Exchange(_exchangeParam.platform, _fromToken, _amount, _toToken, _exchangeAmount);
    }

    /// @notice Report the current asset of strategy
    /// @param _strategy The strategy address
    /// @param _rewardTokens The reward token list
    /// @param _claimAmounts The claim amount list
    /// @param _type 0-harvest(claim); 1-lend; 2-report(without claim);
    function _report(
        address _strategy,
        address[] memory _rewardTokens,
        uint256[] memory _claimAmounts,
        uint256 _lendValue,
        uint256 _type
    ) private {
        StrategyParams memory _strategyParam = strategies[_strategy];
        uint256 _lastStrategyTotalDebt = _strategyParam.totalDebt + _lendValue;
        uint256 _nowStrategyTotalDebt = IStrategy(_strategy).estimatedTotalAssets();
        uint256 _gain;
        uint256 _loss;

        if (_nowStrategyTotalDebt > _lastStrategyTotalDebt) {
            _gain = _nowStrategyTotalDebt - _lastStrategyTotalDebt;
        } else if (_nowStrategyTotalDebt < _lastStrategyTotalDebt) {
            _loss = _lastStrategyTotalDebt - _nowStrategyTotalDebt;
        }

        if (_strategyParam.enforceChangeLimit) {
            if (
                block.timestamp - strategies[_strategy].lastReport < maxTimestampBetweenTwoReported &&
                (_lastStrategyTotalDebt > minCheckedStrategyTotalDebt ||
                    _nowStrategyTotalDebt > minCheckedStrategyTotalDebt)
            ) {
                if (_gain > 0) {
                    require(
                        _gain <= ((_lastStrategyTotalDebt * _strategyParam.profitLimitRatio) / MAX_BPS),
                        "GL" //gain over the profitLimitRatio
                    );
                } else if (_loss > 0) {
                    require(
                        _loss <= ((_lastStrategyTotalDebt * _strategyParam.lossLimitRatio) / MAX_BPS),
                        "LL" //loss over the lossLimitRatio
                    );
                }
            }
        } else {
            strategies[_strategy].enforceChangeLimit = true;
            // The check is turned off only once and turned back on.
        }

        strategies[_strategy].totalDebt = _nowStrategyTotalDebt;
        totalDebt = totalDebt + _nowStrategyTotalDebt + _lendValue - _lastStrategyTotalDebt;

        strategies[_strategy].lastReport = block.timestamp;
        if (_type == 0) {
            strategies[_strategy].lastClaim = block.timestamp;
        }
        emit StrategyReported(
            _strategy,
            _gain,
            _loss,
            _lastStrategyTotalDebt,
            _nowStrategyTotalDebt,
            _rewardTokens,
            _claimAmounts,
            _type
        );
    }

    function _balanceOfToken(address _trackedAsset, address _owner) internal view returns (uint256) {
        uint256 _balance;
        if (_trackedAsset == NativeToken.NATIVE_TOKEN) {
            _balance = _owner.balance;
        } else {
            _balance = IERC20Upgradeable(_trackedAsset).balanceOf(_owner);
        }
        return _balance;
    }

    /// @notice Get the supported asset Decimal
    /// @return _assetDecimal asset Decimals
    function _getAssetDecimals(
        uint256[] memory _assetDecimals,
        uint256 _assetIndex,
        address _asset
    ) internal view returns (uint256) {
        uint256 _decimal = _assetDecimals[_assetIndex];
        if (_decimal == 0) {
            _decimal = trackedAssetDecimalsMap[_asset];
            _assetDecimals[_assetIndex] = _decimal;
        }
        return _decimal;
    }

    /// @notice Get an array of the supported asset prices in USD(USDi)/ETH(ETHi) (1e18)
    /// @return  prices in USD(USDi)/ETH(ETHi) (1e18)
    function _getAssetPrice(
        uint256[] memory _assetPrices,
        uint256 _assetIndex,
        address _asset
    ) internal view returns (uint256) {
        uint256 _price = _assetPrices[_assetIndex];
        if (_price == 0) {
            _price = _getAssetPrice(_asset);
            _assetPrices[_assetIndex] = _price;
        }
        return _price;
    }

    /// @notice Get an array of the supported asset prices in USD(USDi)/ETH(ETHi) (1e18)
    /// @return  _price prices in USD(USDi)/ETH(ETHi) (1e18)
    function _getAssetPrice(address _asset) internal view returns (uint256 _price) {
        //ETHi
        if (vaultType > 0) {
            if (_asset == NativeToken.NATIVE_TOKEN) {
                _price = 1e18;
            } else {
                _price = IValueInterpreter(valueInterpreter).priceInEth(_asset);
            }
        } else {
            _price = IValueInterpreter(valueInterpreter).price(_asset);
        }
    }

    function _checkMintAssets(address[] memory _assets, uint256[] memory _amounts)
        private
        view
        returns (uint256 _ethAmount)
    {
        require(!(IVaultBuffer(vaultBufferAddress).isDistributing()), "ID"); ////is distributing
        uint256 _assetsLength = _assets.length;
        require(
            _assetsLength > 0 && _assetsLength == _amounts.length,
            "ASI" // amounts invalid,Assets and amounts must be equal in length and not empty
        );
        for (uint256 i = 0; i < _assetsLength; i++) {
            address _asset = _assets[i];
            uint256 _amount = _amounts[i];
            checkIsSupportAsset(_asset);
            require(_amount > 0, "ASI"); //Amount must be gt 0
            if (_asset == NativeToken.NATIVE_TOKEN) {
                _ethAmount = _ethAmount + _amount;
            }
        }
    }

    receive() external payable {}

    /// @dev Falldown to the admin implementation
    /// @notice This is a catch all for all functions not declared in core
    fallback() external payable {
        bytes32 _slot = ADMIN_IMPL_POSITION;

        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), sload(_slot), 0, calldatasize(), 0, 0)

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
