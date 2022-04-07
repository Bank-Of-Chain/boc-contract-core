pragma solidity ^0.8.0;
/**
 * @title  Vault Contract
 * @notice The Vault contract defines the storage for the Vault contracts
 * @author BankOfChain Protocol Inc
 */


import "./VaultStorage.sol";
import "../library/BocRoles.sol";

contract Vault is VaultStorage {

    using StableMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using IterableIntMap for IterableIntMap.AddressToIntMap;

    function initialize(
        address _usdi,
        address _accessControlProxy,
        address _treasury,
        address _exchangeManager,
        address _valueInterpreter
    ) public initializer {
        require(_usdi != address(0), "uSDi ad is 0");
        _initAccessControl(_accessControlProxy);

        treasury = _treasury;
        exchangeManager = _exchangeManager;
        valueInterpreter = _valueInterpreter;

        usdi = USDi(_usdi);

        rebasePaused = false;
        // Initial redeem fee of 0 basis points
        redeemFeeBps = 0;
        // Threshold for rebasing
        rebaseThreshold = 1000e18;
    }

    modifier whenNotEmergency() {
        require(!emergencyShutdown, 'ES');
        _;
    }

    modifier whenNotAdjustPosition() {
        require(!adjustPositionPeriod, 'AD');
        _;
    }

    /**
     * @dev Verifies that the rebasing is not paused.
     */
    modifier whenNotRebasePaused() {
        require(!rebasePaused, "RB");
        _;
    }

    modifier isActiveStrategy(address _strategy) {
        require(strategySet.contains(_strategy), "strategy not exist");
        _;
    }

    /// @notice Version of vault
    function getVersion() external pure returns (string memory){
        return "1.0.0";
    }

    /// @notice Minting USDi supported assets
    function getSupportAssets() external view returns (address[] memory){
        return assetSet.values();
    }


    /// @notice Assets held by Vault
    function getTrackedAssets() external view returns (address[] memory){
        return _getTrackedAssets();
    }

    /// @notice Assets held by Vault
    function _getTrackedAssets() internal view returns (address[] memory){
        address[] memory trackedAssets = new address[](trackedAssetsMap.length());
        for (uint256 i = 0; i < trackedAssetsMap.length(); i++) {
            (address trackedAddress,) = trackedAssetsMap.at(i);
            trackedAssets[i] = trackedAddress;
        }
        return trackedAssets;
    }


    /// @notice Vault holds asset value directly in USD (1e18)
    function valueOfTrackedTokens() external view returns (uint256){
        return _totalAssetInVault();
    }


    /// @notice Vault total asset in USD(1e18)
    function totalAssets() external view returns (uint256){
        //return _totalAssetInVault() + _totalAssetInStrategies();
        return _totalAssetInVault() + totalDebt;
    }

    /**
    * @dev Internal to calculate total value of all assets held in Vault.
     * @return _value Total value in USD (1e18)
     */
    function _totalAssetInVault() internal view returns (uint256 _value) {
        for (uint256 i = 0; i < trackedAssetsMap.length(); i++) {
            (address trackedAsset,) = trackedAssetsMap.at(i);
            uint256 balance = IERC20Upgradeable(trackedAsset).balanceOf(address(this));
            if (balance > 0) {
                uint256 decimals = Helpers.getDecimals(trackedAsset);
                _value = _value + (balance.scaleBy(18, decimals));
            }
        }
    }

    //    /**
    //     * @dev Internal to calculate total value of all assets held in Strategies.
    //     * @return _value Total value in USD (1e18)
    //     */
    //    function _totalAssetInStrategies() internal view returns (uint256 _value) {
    //        uint256[] memory _assetDecimals = _getAssetDecimals();
    //        for (uint256 i = 0; i < strategySet.length(); i++) {
    //            _value = _value + _checkBalanceInStrategy(strategySet.at(i), _assetDecimals);
    //        }
    //    }

    /// @notice All strategies
    function getStrategies() external view returns (address[] memory){
        return strategySet.values();
    }

    /// @notice estimate Minting USDi with stablecoins
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @dev Support single asset or multi-assets
    /// @return unitAdjustedDeposit  assets amount by Scale up to 18 decimal
    /// @return priceAdjustedDeposit   usdi amount
    function estimateMint(address[] memory _assets, uint256[] memory _amounts) public view returns (uint256 unitAdjustedDeposit, uint256 priceAdjustedDeposit){
        require(_assets.length > 0 && _amounts.length > 0 && _assets.length == _amounts.length, "Assets or amounts must not be empty and Assets length must equal amounts length");
        bool amountsGreaterThanZero = true;
        bool assetsExist = true;

        for (uint256 i = 0; i < _assets.length; i++) {
            assetsExist = assetSet.contains(_assets[i]);
            if (assetsExist == false) {
                break;
            }
            amountsGreaterThanZero = (_amounts[i] > 0);
            if (amountsGreaterThanZero == false) {
                break;
            }
        }
        require(assetsExist, "Asset is not exist");
        require(amountsGreaterThanZero, "Amount must be greater than 0");
        for (uint256 i = 0; i < _assets.length; i++) {
            uint256 price = _priceUSDMint(_assets[i]);
            uint256 assetDecimals = Helpers.getDecimals(_assets[i]);
            // Scale up to 18 decimal
            unitAdjustedDeposit = unitAdjustedDeposit + (_amounts[i].scaleBy(18, assetDecimals));
            priceAdjustedDeposit = priceAdjustedDeposit + (_amounts[i].mulTruncateScale(price, 10 ** assetDecimals));
        }
        return (unitAdjustedDeposit, priceAdjustedDeposit);
    }

    /// @notice Minting USDi with stablecoins
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @param _minimumUsdiAmount Minimum USDI to mint
    /// @dev Support single asset or multi-assets
    function mint(address[] memory _assets, uint256[] memory _amounts, uint256 _minimumUsdiAmount) external whenNotEmergency whenNotAdjustPosition nonReentrant returns (uint256) {

        uint256 unitAdjustedDeposit = 0;
        uint256 priceAdjustedDeposit = 0;
        (unitAdjustedDeposit, priceAdjustedDeposit) = estimateMint(_assets, _amounts);
        if (_minimumUsdiAmount > 0) {
            require(
                priceAdjustedDeposit >= _minimumUsdiAmount,
                "Mint amount lower than minimum"
            );
        }

        // Rebase must happen before any transfers occur.
        if (unitAdjustedDeposit >= rebaseThreshold && !rebasePaused) {
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
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            address _strategy = withdrawQueue[i];
            if (_strategy == ZERO_ADDRESS) break;

            if (!strategySet.contains(_strategy)) {
                continue;
            }
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
            IStrategy strategy = IStrategy(_strategy);
            // console.log('start withdrawn from %s numerator %d denominator %d', _strategy, strategyWithdrawValue, strategyTotalValue);
            strategy.repay(strategyWithdrawValue, strategyTotalValue);

            strategies[_strategy].totalDebt -= strategyWithdrawValue;
            totalDebt -= strategyWithdrawValue;

            if (needWithdrawValue <= 0) {
                break;
            }
        }
    }

    /// @notice calculate need transfer amount from vault ,set to outputs
    function _calculateOutputs(uint256 _needTransferAmount, uint256[] memory _assetRedeemPrices, uint256[] memory _assetDecimals) internal returns (uint256[] memory){
        uint256[] memory outputs = new uint256[](trackedAssetsMap.length());

        for (uint256 i = trackedAssetsMap.length(); i > 0; i--) {
            (address trackedAsset,) = trackedAssetsMap.at(i - 1);
            uint256 balance = IERC20Upgradeable(trackedAsset).balanceOf(address(this));
            if (balance > 0) {
                uint256 _value = balance.mulTruncateScale(_assetRedeemPrices[i - 1], 10 ** _assetDecimals[i - 1]);
                if (_value >= _needTransferAmount) {
                    outputs[i - 1] = balance.scaleBy(18, _assetDecimals[i - 1]) * _needTransferAmount / _value;
                    break;
                } else {
                    outputs[i - 1] = balance.scaleBy(18, _assetDecimals[i - 1]);
                    _needTransferAmount = _needTransferAmount - _value;
                }
            }
        }
        return outputs;
    }

    // @notice exchange token to _asset form vault and transfer to user
    function _exchangeAndTransfer(address _asset, uint256[] memory outputs, uint256[] memory _assetDecimals, IExchangeAggregator.ExchangeToken[] memory _exchangeTokens) internal returns (address[]  memory _assets, uint256[] memory _amounts, uint256 _actualAmount){
        uint256 _toDecimals = Helpers.getDecimals(_asset);
        for (uint256 i = 0; i < trackedAssetsMap.length(); i++) {
            (address withdrawToken,) = trackedAssetsMap.at(i);
            uint256 withdrawDecimals = _assetDecimals[i];
            uint256 withdrawAmount = outputs[i].scaleBy(withdrawDecimals, 18);
            if (withdrawAmount > 0) {
                if (withdrawToken == _asset) {
                    _actualAmount = _actualAmount + outputs[i];
                } else {
                    for (uint256 j = 0; j < _exchangeTokens.length; j++) {
                        IExchangeAggregator.ExchangeToken memory exchangeToken = _exchangeTokens[j];
                        if (exchangeToken.fromToken == withdrawToken && exchangeToken.toToken == _asset) {
                            uint256 toAmount = _exchange(exchangeToken.fromToken, exchangeToken.toToken, withdrawAmount, exchangeToken.exchangeParam);
                            // console.log('withdraw exchange token %s amount %d toAmount %d', withdrawAmount, withdrawAmount, toAmount);
                            _actualAmount = _actualAmount + (toAmount.scaleBy(18, _toDecimals));
                            break;
                        }
                    }
                }
            }
        }
        uint256 _amount = _actualAmount.scaleBy(_toDecimals, 18);

        if (IERC20Upgradeable(_asset).balanceOf(address(this)) >= _amount) {
            // Use Vault funds first if sufficient
            IERC20Upgradeable(_asset).safeTransfer(msg.sender, _amount);
        } else {
            revert("Liquidity error");
        }
        _assets = new address[](1);
        _assets[0] = _asset;
        _amounts = new uint256[](1);
        _amounts[0] = _amount;
    }

    // @notice without exchange token and transfer form vault to user
    function _withoutExchangeTransfer(uint256[] memory outputs, uint256[] memory _assetDecimals) internal returns (address[]  memory _assets, uint256[] memory _amounts, uint256 _actualAmount){
        for (uint256 i = 0; i < trackedAssetsMap.length(); i++) {
            _actualAmount = _actualAmount + outputs[i];
            (address withdrawToken,) = trackedAssetsMap.at(i);
            uint256 withdrawDecimals = _assetDecimals[i];
            outputs[i] = outputs[i].scaleBy(withdrawDecimals, 18);
            if (outputs[i] > 0) {
                if (IERC20Upgradeable(withdrawToken).balanceOf(address(this)) >= outputs[i]) {
                    // Use Vault funds first if sufficient
                    IERC20Upgradeable(withdrawToken).safeTransfer(msg.sender, outputs[i]);
                } else {
                    revert("Liquidity error");
                }
            }
        }
        _assets = _getTrackedAssets();
        _amounts = outputs;
    }

    /**
    * @notice Get an array of the supported asset Decimals
     * @return _assetDecimals Array of asset Decimals
     */
    function _getAssetDecimals()
    internal
    view
    returns (uint256[] memory _assetDecimals)    {
        _assetDecimals = new uint256[](trackedAssetsMap.length());
        for (uint256 i = 0; i < trackedAssetsMap.length(); i++) {
            (address trackedAsset,) = trackedAssetsMap.at(i);
            _assetDecimals[i] = Helpers.getDecimals(trackedAsset);
        }
    }

    /// @notice burn USDi,return stablecoins
    /// @param _amount Amount of USDi to burn
    /// @param _asset one of StableCoin asset
    /// @param _minimumUnitAmount Minimum stablecoin units to receive in return
    function burn(uint256 _amount,
        address _asset,
        uint256 _minimumUnitAmount,
        bool _needExchange,
        IExchangeAggregator.ExchangeToken[] memory _exchangeTokens
    ) external whenNotEmergency whenNotAdjustPosition nonReentrant returns (address[] memory _assets, uint256[] memory _amounts){
        require(_amount > 0 && _amount <= usdi.balanceOf(msg.sender), "Amount must be greater than 0 and less than or equal to balance");
        require(assetSet.contains(_asset), "The asset not support");
        bool toTokenValid = true;
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            toTokenValid = (_exchangeTokens[i].toToken == _asset);
            if (toTokenValid == false) {
                break;
            }
        }
        require(toTokenValid, "toToken is invalid");

        uint256[] memory _assetRedeemPrices = _getAssetRedeemPrices();
        uint256[] memory _assetDecimals = _getAssetDecimals();
        uint256[] memory _assetBalancesInVault = new uint256[](trackedAssetsMap.length());
        for (uint256 i = 0; i < trackedAssetsMap.length(); i++) {
            (address trackedAsset,) = trackedAssetsMap.at(i);
            _assetBalancesInVault[i] = IERC20Upgradeable(trackedAsset).balanceOf(address(this));
        }

        if (maxSupplyDiff > 0) {
            uint256 _totalValueInStrategy = 0;
            uint256 strategyLength = strategySet.length();
            for (uint256 i = 0; i < strategyLength; i++) {
                _totalValueInStrategy = _totalValueInStrategy + IStrategy(strategySet.at(i)).checkBalance();
            }

            uint256 _totalValueInValue = 0;
            for (uint256 i = 0; i < _assetBalancesInVault.length; i++) {
                if (_assetBalancesInVault[i] > 0) {
                    _totalValueInValue = _totalValueInValue + (_assetBalancesInVault[i].scaleBy(18, _assetDecimals[i]));
                }
            }

            // Check that USDI is backed by enough assets
            uint256 _totalSupply = usdi.totalSupply();
            // Allow a max difference of maxSupplyDiff% between
            // backing assets value and OUSD total supply
            uint256 diff = _totalSupply.divPrecisely(_totalValueInValue + _totalValueInStrategy);
            require(
                (diff > 1e18 ? (diff - (1e18)) : (uint256(1e18) - (diff))) <=
                maxSupplyDiff,
                "Backing supply liquidity error"
            );
        }

        uint256 _burnAmount = _amount;
        uint256 _redeemFee = 0;
        // Calculate redeem fee
        if (redeemFeeBps > 0) {
            _redeemFee = _amount * redeemFeeBps / 10000;
            _burnAmount = _burnAmount - _redeemFee;
        }
        //redeem price in vault
        uint256 _totalAssetInVault = 0;
        for (uint256 i = 0; i < _assetBalancesInVault.length; i++) {
            if (_assetBalancesInVault[i] > 0) {
                _totalAssetInVault = _totalAssetInVault + (_assetBalancesInVault[i].mulTruncateScale(_assetRedeemPrices[i], 10 ** _assetDecimals[i]));
            }
        }

        // vault not enough,withdraw from withdraw queue strategy
        if (_totalAssetInVault < _burnAmount) {
            _repayFromWithdrawQueue(_burnAmount - _totalAssetInVault);
        }
        // calculate need transfer amount from vault ,set to outputs
        uint256[] memory outputs = _calculateOutputs(_burnAmount, _assetRedeemPrices, _assetDecimals);

        uint256 _actualAmount = 0;
        if (_needExchange) {
            (_assets, _amounts, _actualAmount) = _exchangeAndTransfer(_asset, outputs, _assetDecimals, _exchangeTokens);
        } else {
            (_assets, _amounts, _actualAmount) = _withoutExchangeTransfer(outputs, _assetDecimals);
        }

        if (_minimumUnitAmount > 0) {
            require(
                _actualAmount >= _minimumUnitAmount,
                "amount lower than minimum"
            );
        }
        _burnUSDIAndCheckRebase(_asset, _burnAmount + _redeemFee, _burnAmount);
    }

    // @notice burn usdi and check rebase
    function _burnUSDIAndCheckRebase(address _asset, uint256 _amount, uint256 _burnAmount) internal {
        usdi.burn(msg.sender, _burnAmount);

        // Until we can prove that we won't affect the prices of our assets
        // by withdrawing them, this should be here.
        // It's possible that a strategy was off on its asset total, perhaps
        // a reward token sold for more or for less than anticipated.
        if (_burnAmount > rebaseThreshold && !rebasePaused) {
            _rebase();
        }
        emit Burn(msg.sender, _asset, _amount, _burnAmount);
    }


    /**
    * @notice Get an array of the supported asset prices in USD.
     * @return assetPrices Array of asset prices in USD (1e18)
     */
    function _getAssetRedeemPrices()
    internal
    view
    returns (uint256[] memory assetPrices)    {
        assetPrices = new uint256[](trackedAssetsMap.length());

        IValueInterpreter valueInterpreter = IValueInterpreter(valueInterpreter);
        // Price from Oracle is returned with 8 decimals
        // _amount is in assetDecimals
        for (uint256 i = 0; i < trackedAssetsMap.length(); i++) {
            (address trackedAsset,) = trackedAssetsMap.at(i);
            uint256 price = valueInterpreter.price(trackedAsset);
            if (price < 1e18) {
                price = 1e18;
            }
            // Price from Oracle is returned with 8 decimals so scale to 18
            assetPrices[i] = price;
        }
    }
    //
    //    /**
    //    * @notice Get the balance of an asset held in strategy.
    //     * @param _strategy Address of strategy
    //     * @param _assetDecimals Array of asset Decimals
    //     * @return balance Balance of strategy usd (1e18)
    //     */
    //    function _checkBalanceInStrategy(address _strategy, uint256[] memory _assetDecimals) internal view returns (uint256){
    //        IStrategy strategy = IStrategy(_strategy);
    //        (address[] memory _tokens, uint256[] memory _amounts, bool isUsd, uint256 usdValue) = strategy.checkBalance();
    //        uint256 strategyAssetValue = 0;
    //        if (isUsd) {
    //            strategyAssetValue = usdValue;
    //        } else {
    //            uint256 trackedAssetsLength = trackedAssetsMap.length();
    //            for (uint256 i = 0; i < _tokens.length; i++) {
    //                if (_amounts[i] > 0) {
    //                    for (uint256 j = 0; j < trackedAssetsLength; j++) {
    //                        (address trackedAsset,) = trackedAssetsMap.at(j);
    //                        if (trackedAsset == _tokens[i]) {
    //                            strategyAssetValue = strategyAssetValue + (_amounts[i].scaleBy(18, _assetDecimals[j]));
    //                            break;
    //                        }
    //                    }
    //                }
    //            }
    //        }
    //        return strategyAssetValue;
    //    }
    //
    //    /**
    //    * @notice Get the value of an asset held in strategy. by redeempirce
    //     * @param _strategy Address of strategy
    //     * @return balance Balance of strategy usd (1e18)
    //     */
    //    function _checkValueInStrategyByRedeem(address _strategy, uint256[] memory assetDecimals, uint256[] memory assetRedeemPrices) internal view returns (uint256){
    //        IStrategy strategy = IStrategy(_strategy);
    //        (address[] memory _tokens, uint256[] memory _amounts, bool isUsd, uint256 usdValue) = strategy.getPositionDetail();
    //        uint256 strategyAssetValue = 0;
    //        if (isUsd) {
    //            strategyAssetValue = usdValue;
    //        } else {
    //            uint256 trackedAssetsLength = trackedAssetsMap.length();
    //            for (uint256 i = 0; i < _tokens.length; i++) {
    //                if (_amounts[i] > 0) {
    //                    for (uint256 j = 0; j < trackedAssetsLength; j++) {
    //                        (address trackedAsset,) = trackedAssetsMap.at(j);
    //                        if (trackedAsset == _tokens[i]) {
    //                            strategyAssetValue = strategyAssetValue + (_amounts[i].mulTruncateScale(assetRedeemPrices[j], 10 ** assetDecimals[j]));
    //                            break;
    //                        }
    //                    }
    //                }
    //            }
    //        }
    //        return strategyAssetValue;
    //    }

    /// @notice Change USDi supply with Vault total assets.
    function rebase() external nonReentrant {
        _rebase();
    }

    /**
     * @dev Calculate the total value of assets held by the Vault and all
     *      strategies and update the supply of OUSD, optionally sending a
     *      portion of the yield to the trustee.
     */
    function _rebase() internal whenNotEmergency whenNotRebasePaused {
        uint256 usdiSupply = usdi.totalSupply();
        if (usdiSupply == 0 || usdi.rebasingCredits() < 1e18) {
            return;
        }

        //        uint256 vaultValue = _totalAssetInVault() + _totalAssetInStrategies();
        uint256 vaultValue = _totalAssetInVault() + totalDebt;

        // Yield fee collection
        address _treasuryAddress = treasury;
        // gas savings
        if (trusteeFeeBps > 0 && _treasuryAddress != address(0) && (vaultValue > usdiSupply)) {
            uint256 yield = vaultValue - usdiSupply;
            uint256 fee = yield * trusteeFeeBps / 10000;
            require(yield > fee, "Fee must not be greater than yield");
            if (fee > 0) {
                usdi.mint(_treasuryAddress, fee);
            }
        }

        // Only rachet USDi supply upwards
        usdiSupply = usdi.totalSupply();
        // Final check should use latest value
        if (vaultValue > usdiSupply) {
            usdi.changeSupply(vaultValue);
        }
    }

    /// @notice Allocate funds in Vault to strategies.
    function lend(address _strategy, IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens) external isKeeper whenNotEmergency isActiveStrategy(_strategy) nonReentrant {
        (address[] memory _wants, uint256[] memory _ratios,uint256[] memory toAmounts) = _checkAndExchange(_strategy, _exchangeTokens);
        //Definition rule 0 means unconstrained, currencies that do not participate are not in the returned wants
        uint256 minProductIndex = 0;
        bool isWantRatioIgnorable = IStrategy(_strategy).isWantRatioIgnorable();
        if (!isWantRatioIgnorable && _ratios.length > 1) {
            for (uint256 i = 0; i < _ratios.length; i++) {
                // console.log('token %s amount %d aspect %d', _wants[i], toAmounts[i], _ratios[i]);
                // console.log('token i+1  %s amount %d aspect %d', tokenDetails[i + 1].token, tokenDetails[i + 1].amount, tokenAspects[i + 1].aspect);
                if (_ratios[i] == 0) {
                    //0 is free
                    continue;
                } else if (_ratios[minProductIndex] == 0) {
                    //minProductIndex is assigned to the first index whose proportion is not 0
                    minProductIndex = i;
                } else if (toAmounts[minProductIndex] * _ratios[i] > toAmounts[i] * _ratios[minProductIndex]) {
                    minProductIndex = i;
                }
            }
        }

        uint256 minMount = toAmounts[minProductIndex];
        uint256 minAspect = _ratios[minProductIndex];
        uint256 lendValue;
        for (uint256 i = 0; i < toAmounts.length; i++) {
            if (toAmounts[i] > 0) {
                uint256 decimals = Helpers.getDecimals(_wants[i]);
                // console.log('token %s amount %d', _wants[i], toAmounts[i]);
                // console.log(' minProductIndex %d minMount %d minAspect %d', minProductIndex, minMount, minAspect);
                uint256 actualAmount = toAmounts[i];
                if (!isWantRatioIgnorable && _ratios[i] > 0) {
                    actualAmount = _ratios[i] * minMount / minAspect;
                }
                lendValue += actualAmount.scaleBy(18, decimals);

                toAmounts[i] = actualAmount;
                // console.log('token %s actual amount %d', _wants[i], actualAmount);
                IERC20Upgradeable(_wants[i]).safeTransfer(_strategy, actualAmount);
            }
        }
        IStrategy strategy = IStrategy(_strategy);
        strategy.borrow(_wants, toAmounts);
        strategies[_strategy].totalDebt += lendValue;
        totalDebt += lendValue;

        emit LendToStrategy(_strategy, _wants, toAmounts, lendValue);
    }

    /// @notice check valid and exchange to want token
    function _checkAndExchange(address _strategy, IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens) internal returns (address[] memory _wants, uint256[] memory _ratios, uint256[] memory toAmounts){
        (_wants, _ratios) = IStrategy(_strategy).getWantsInfo();
        toAmounts = new uint256[](_wants.length);
        bool toTokenValid = true;
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            bool findToToken = false;
            for (uint256 j = 0; j < _wants.length; j++) {
                if (_exchangeTokens[i].toToken == _wants[j]) {
                    findToToken = true;
                    break;
                }
            }
            if (findToToken == false) {
                toTokenValid = false;
                break;
            }
        }
        require(toTokenValid, "toToken invalid");

        for (uint256 j = 0; j < _wants.length; j++) {
            for (uint256 i = 0; i < _exchangeTokens.length; i++) {
                IExchangeAggregator.ExchangeToken memory exchangeToken = _exchangeTokens[i];

                // not strategy need token,skip
                if (_wants[j] != exchangeToken.toToken) continue;

                uint256 toAmount;
                if (exchangeToken.fromToken == exchangeToken.toToken) {
                    toAmount = exchangeToken.fromAmount;
                } else {
                    if (exchangeToken.fromAmount > 0) {
                        toAmount = _exchange(exchangeToken.fromToken, exchangeToken.toToken, exchangeToken.fromAmount, exchangeToken.exchangeParam);
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
    ) external isKeeper returns (uint256) {
        return _exchange(_fromToken, _toToken, _amount, exchangeParam);
    }

    function _exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory exchangeParam
    ) internal returns (uint256 exchangeAmount) {
        require(trackedAssetsMap.contains(_toToken), '!T');

        IExchangeAdapter.SwapDescription memory swapDescription = IExchangeAdapter.SwapDescription({
        amount : _amount,
        srcToken : _fromToken,
        dstToken : _toToken,
        receiver : address(this)
        });
        IERC20Upgradeable(_fromToken).safeApprove(exchangeManager, _amount);
        exchangeAmount = IExchangeAggregator(exchangeManager).swap(exchangeParam.platform, exchangeParam.method, exchangeParam.encodeExchangeArgs, swapDescription);
        uint256 oracleExpectedAmount = IValueInterpreter(valueInterpreter).calcCanonicalAssetValue(_fromToken, _amount, _toToken);
        require(exchangeAmount >= oracleExpectedAmount * (MAX_BPS - exchangeParam.slippage - exchangeParam.oracleAdditionalSlippage) / MAX_BPS, 'OL');
        emit Exchange(exchangeParam.platform, _fromToken, _amount, _toToken, exchangeAmount);
    }

    /// @notice redeem the funds from specified strategy.
    function redeem(address _strategy, uint256 _amount) external isKeeper isActiveStrategy(_strategy) nonReentrant {
        uint256 strategyAssetValue = strategies[_strategy].totalDebt;
        require(_amount <= strategyAssetValue);

        IStrategy strategy = IStrategy(_strategy);
        (address[] memory _assets, uint256[] memory _amounts) = strategy.repay(_amount, strategyAssetValue);

        strategies[_strategy].totalDebt -= _amount;
        totalDebt -= _amount;

        // console.log('[vault.redeem] %s redeem _amount %d totalDebt %d ', _strategy, _amount, strategyAssetValue);
        emit Redeem(_strategy, _amount, _assets, _amounts);
    }

    function report(uint256 _strategyAsset) external isActiveStrategy(msg.sender) {

        uint256 lastStrategyTotalDebt = strategies[msg.sender].totalDebt;
        uint256 nowStrategyTotalDebt = _strategyAsset;
        uint256 gain = 0;
        uint256 loss = 0;

        if (nowStrategyTotalDebt > lastStrategyTotalDebt) {
            gain = nowStrategyTotalDebt - lastStrategyTotalDebt;
        } else if (nowStrategyTotalDebt < lastStrategyTotalDebt) {
            loss = lastStrategyTotalDebt - nowStrategyTotalDebt;
        }

        if (strategies[msg.sender].enforceChangeLimit) {
            if (gain > 0) {
                require(gain <= ((lastStrategyTotalDebt * strategies[msg.sender].profitLimitRatio) / MAX_BPS), 'GL');
            } else if (loss > 0) {
                require(loss <= ((lastStrategyTotalDebt * strategies[msg.sender].lossLimitRatio) / MAX_BPS), 'LL');
            }
        } else {
            strategies[msg.sender].enforceChangeLimit = true;
            // The check is turned off only once and turned back on.
        }

        strategies[msg.sender].totalDebt = nowStrategyTotalDebt;
        totalDebt = totalDebt - lastStrategyTotalDebt + nowStrategyTotalDebt;

        strategies[msg.sender].lastReport = block.timestamp;
        //        lastReport = block.timestamp;

        //        emit StrategyReported(msg.sender, gain, loss, lastStrategyTotalDebt, nowStrategyTotalDebt);
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
        // Price from Oracle is returned with 8 decimals so scale to 18
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
            let result := delegatecall(gas(), sload(slot), 0, calldatasize(), 0, 0)

        // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return (0, returndatasize())
            }
        }
    }
}