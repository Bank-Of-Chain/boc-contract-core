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

    // Only smart contracts will be affected by this modifier
    modifier defense() {
        require((msg.sender == tx.origin) || whiteList[msg.sender]);
        _;
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


    /// @notice Shutdown the vault when an emergency occurs, cannot mint/burn.
    function setEmergencyShutdown(bool active) external isVaultManager {
        emergencyShutdown = active;
        emit SetEmergencyShutdown(active);
    }

    /// @notice set adjustPositionPeriod true when adjust position occurs, cannot remove add asset/strategy and cannot mint/burn.
    function setAdjustPositionPeriod(bool _adjustPositionPeriod) external isVaultManager {
        adjustPositionPeriod = _adjustPositionPeriod;
        emit SetAdjustPositionPeriod(_adjustPositionPeriod);
    }

    /**
     * @dev Set a minimum amount of OUSD in a mint or redeem that triggers a
         * rebase
         * @param _threshold OUSD amount with 18 fixed decimals.
         */
    function setRebaseThreshold(uint256 _threshold) external isVaultManager {
        rebaseThreshold = _threshold;
        emit RebaseThresholdUpdated(_threshold);
    }

    /**
     * @dev Set a fee in basis points to be charged for a redeem.
         * @param _redeemFeeBps Basis point fee to be charged
         */
    function setRedeemFeeBps(uint256 _redeemFeeBps) external isVaultManager {
        require(_redeemFeeBps <= 1000, "Redeem fee should not be over 10%");
        redeemFeeBps = _redeemFeeBps;
        emit RedeemFeeUpdated(_redeemFeeBps);
    }

    /**
        * @dev Sets the maximum allowable difference between
         * total supply and backing assets' value.
         */
    function setMaxSupplyDiff(uint256 _maxSupplyDiff) external isVaultManager {
        maxSupplyDiff = _maxSupplyDiff;
        emit MaxSupplyDiffChanged(_maxSupplyDiff);
    }

    /**
     * @dev Sets the treasuryAddress that can receive a portion of yield.
         *      Setting to the zero address disables this feature.
         */
    function setTreasuryAddress(address _address) external onlyRole(BocRoles.GOV_ROLE) {
        treasury = _address;
        emit TreasuryAddressChanged(_address);
    }

    /**
     * @dev Sets the TrusteeFeeBps to the percentage of yield that should be
         *      received in basis points.
         */
    function setTrusteeFeeBps(uint256 _basis) external isVaultManager {
        require(_basis <= 5000, "basis cannot exceed 50%");
        trusteeFeeBps = _basis;
        emit TrusteeFeeBpsChanged(_basis);
    }

    //advance queue
    function setWithdrawalQueue(address[] memory queues) external isKeeper {
        bool strategyExist = true;
        for (uint256 i = 0; i < queues.length; i++) {
            strategyExist = strategySet.contains(queues[i]);
            if (strategyExist == false) {
                break;
            }
        }
        require(strategyExist, 'strategy not exist');
        for (uint256 i = 0; i < queues.length; i++) {
            address strategy = queues[i];
            if (i < withdrawQueue.length) {
                withdrawQueue[i] = strategy;
            } else {
                withdrawQueue.push(strategy);
            }
        }
        for (uint256 i = queues.length; i < withdrawQueue.length; i++) {
            if (withdrawQueue[i] == ZERO_ADDRESS) break;
            withdrawQueue[i] = ZERO_ADDRESS;
        }
        emit SetWithdrawalQueue(queues);
    }


    /***************************************
                       Pause
       ****************************************/

    /**
     * @dev Set the deposit paused flag to true to prevent rebasing.
     */
    function pauseRebase() external isVaultManager {
        rebasePaused = true;
        emit RebasePaused();
    }

    /**
     * @dev Set the deposit paused flag to true to allow rebasing.
     */
    function unpauseRebase() external isVaultManager {
        rebasePaused = false;
        emit RebaseUnpaused();
    }

    /// @notice Version of vault
    function getVersion() external pure returns (string memory){
        return "1.5";
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
        return _totalAssetInVault() + _totalAssetInStrategies();
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

    /**
     * @dev Internal to calculate total value of all assets held in Strategies.
     * @return _value Total value in USD (1e18)
     */
    function _totalAssetInStrategies() internal view returns (uint256 _value) {
        uint256[] memory _assetDecimals = _getAssetDecimals();
        for (uint256 i = 0; i < strategySet.length(); i++) {
            _value = _value + _checkBalanceInStrategy(strategySet.at(i), _assetDecimals);
        }
    }

    /// @notice All strategies
    function getStrategies() external view returns (address[] memory){
        return strategySet.values();
    }

    /// @notice Added support for specific asset.
    function addAsset(address _asset) external isVaultManager whenNotEmergency whenNotAdjustPosition defense {
        require(!assetSet.contains(_asset), "existed");
        assetSet.add(_asset);
        // Verify that our oracle supports the asset
        // slither-disable-next-line unused-return
        IValueInterpreter(valueInterpreter).price(_asset);
        trackedAssetsMap.plus(_asset, 1);
        emit AddAsset(_asset);
    }

    /// @notice Remove support for specific asset.
    function removeAsset(address _asset) external isVaultManager whenNotEmergency whenNotAdjustPosition defense {
        require(assetSet.contains(_asset), "not exist");
        assetSet.remove(_asset);
        trackedAssetsMap.minus(_asset, 1);
        if (trackedAssetsMap.get(_asset) <= 0 && IERC20Upgradeable(_asset).balanceOf(address(this)) == 0) {
            trackedAssetsMap.remove(_asset);
        }
        emit RemoveAsset(_asset);
    }

    /// @notice Add strategy to strategy list
    /// @dev The strategy added to the strategy list,
    ///      Vault may invest funds into the strategy,
    ///      and the strategy will invest the funds in the 3rd protocol
    function addStrategy(address[] memory _strategies) external isVaultManager whenNotEmergency whenNotAdjustPosition defense {
        bool addressValid = true;
        bool strategyNotExist = true;
        bool vaultValid = true;
        for (uint256 i = 0; i < _strategies.length; i++) {
            addressValid = (_strategies[i] != ZERO_ADDRESS);
            if (addressValid == false) {
                break;
            }
            strategyNotExist = !strategySet.contains(_strategies[i]);
            if (strategyNotExist == false) {
                break;
            }
            vaultValid = (IStrategy(_strategies[i]).vault() == address(this));
            if (vaultValid == false) {
                break;
            }
        }
        require(addressValid && strategyNotExist && vaultValid, "Strategy is invalid");

        for (uint256 i = 0; i < _strategies.length; i++) {
            strategySet.add(_strategies[i]);
            address[] memory _wants = IStrategy(_strategies[i]).getWants();
            for (uint j = 0; j < _wants.length; j++) {
                trackedAssetsMap.plus(_wants[j], 1);
            }
        }

        emit AddStrategies(_strategies);
    }


    /// @notice Remove strategy from strategy list
    /// @dev The removed policy withdraws funds from the 3rd protocol and returns to the Vault
    function removeStrategy(address[] memory _strategies) external isVaultManager whenNotEmergency whenNotAdjustPosition defense {
        bool strategyExist = true;
        for (uint256 i = 0; i < _strategies.length; i++) {
            strategyExist = strategySet.contains(_strategies[i]);
            if (strategyExist == false) {
                break;
            }
        }
        require(strategyExist, "Strategy not exist");

        for (uint256 i = 0; i < _strategies.length; i++) {
            _removeStrategy(_strategies[i], false);
        }
        emit RemoveStrategies(_strategies);
    }

    function forceRemoveStrategy(address _strategy) external onlyGovOrDelegate {
        _removeStrategy(_strategy, true);
    }

    /**
    * @dev Remove a strategy from the Vault.
     * @param _addr Address of the strategy to remove
     */
    function _removeStrategy(address _addr, bool _force) internal {
        // Withdraw all assets
        try IStrategy(_addr).repay(MAX_BPS, MAX_BPS) {
        } catch {
            if (!_force) {
                revert();
            }
        }

        address[] memory _wants = IStrategy(_addr).getWants();
        for (uint i = 0; i < _wants.length; i++) {
            address wantToken = _wants[i];
            trackedAssetsMap.minus(wantToken, 1);
            if (trackedAssetsMap.get(wantToken) <= 0 && IERC20Upgradeable(wantToken).balanceOf(address(this)) == 0) {
                trackedAssetsMap.remove(wantToken);
            }
        }
        strategySet.remove(_addr);
        _removeStrategyFromQueue(_addr);
    }

    /// @notice Minting USDi with stablecoins
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @param _minimumUsdiAmount Minimum USDI to mint
    /// @dev Support single asset or multi-assets
    function mint(address[] memory _assets, uint256[] memory _amounts, uint256 _minimumUsdiAmount) external whenNotEmergency whenNotAdjustPosition defense {
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
        uint256 unitAdjustedDeposit = 0;
        uint256 priceAdjustedDeposit = 0;
        for (uint256 i = 0; i < _assets.length; i++) {
            uint256 price = _priceUSDMint(_assets[i]);
            uint256 assetDecimals = Helpers.getDecimals(_assets[i]);
            // Scale up to 18 decimal
            unitAdjustedDeposit = unitAdjustedDeposit + (_amounts[i].scaleBy(18, assetDecimals));
            priceAdjustedDeposit = priceAdjustedDeposit + (_amounts[i].mulTruncateScale(price, 10 ** assetDecimals));
        }
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
    }

    /// @notice withdraw from strategy queue
    function _repayFromWithdrawQueue(uint256 needWithdrawValue, uint256[] memory _assetDecimals, uint256[] memory _assetRedeemPrices) internal {
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            address _strategy = withdrawQueue[i];
            if (_strategy == ZERO_ADDRESS) break;

            if (!strategySet.contains(_strategy)) {
                continue;
            }
            uint256 strategyTotalValue = _checkValueInStrategyByRedeem(_strategy, _assetDecimals, _assetRedeemPrices);

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

            if (needWithdrawValue <= 0) {
                break;
            }
        }
    }

    /// @notice calculate need transfer amount from vault ,set to outputs
    function _calculateOutputs(uint256 _needTransferAmount, uint256[] memory _assetRedeemPrices, uint256[] memory _assetDecimals) internal returns (uint256[] memory){
        uint256[] memory outputs = new uint256[](trackedAssetsMap.length());

        for (uint256 i = trackedAssetsMap.length() - 1; i >= 0; i--) {
            (address trackedAsset,) = trackedAssetsMap.at(i);
            uint256 balance = IERC20Upgradeable(trackedAsset).balanceOf(address(this));
            if (balance > 0) {
                uint256 _value = balance.mulTruncateScale(_assetRedeemPrices[i], 10 ** _assetDecimals[i]);
                if (_value >= _needTransferAmount) {
                    outputs[i] = balance.scaleBy(18, _assetDecimals[i]) * _needTransferAmount / _value;
                    break;
                } else {
                    outputs[i] = balance.scaleBy(18, _assetDecimals[i]);
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
    ) external whenNotEmergency whenNotAdjustPosition defense returns (address[] memory _assets, uint256[] memory _amounts){
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
                _totalValueInStrategy = _totalValueInStrategy + _checkBalanceInStrategy(strategySet.at(i), _assetDecimals);
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
            _repayFromWithdrawQueue(_burnAmount - _totalAssetInVault, _assetDecimals, _assetRedeemPrices);
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
            if (price < 1e8) {
                price = 1e8;
            }
            // Price from Oracle is returned with 8 decimals so scale to 18
            assetPrices[i] = price.scaleBy(18, 8);
        }
    }

    /**
    * @notice Get the balance of an asset held in strategy.
     * @param _strategy Address of strategy
     * @param _assetDecimals Array of asset Decimals
     * @return balance Balance of strategy usd (1e18)
     */
    function _checkBalanceInStrategy(address _strategy, uint256[] memory _assetDecimals) internal view returns (uint256){
        IStrategy strategy = IStrategy(_strategy);
        (address[] memory _tokens, uint256[] memory _amounts, bool isUsd, uint256 usdValue) = strategy.getPositionDetail();
        uint256 strategyAssetValue = 0;
        if (isUsd) {
            strategyAssetValue = usdValue;
        } else {
            uint256 trackedAssetsLength = trackedAssetsMap.length();
            for (uint256 i = 0; i < _tokens.length; i++) {
                if (_amounts[i] > 0) {
                    for (uint256 j = 0; j < trackedAssetsLength; j++) {
                        (address trackedAsset,) = trackedAssetsMap.at(j);
                        if (trackedAsset == _tokens[i]) {
                            strategyAssetValue = strategyAssetValue + (_amounts[i].scaleBy(18, _assetDecimals[j]));
                            break;
                        }
                    }
                }
            }
        }
        return strategyAssetValue;
    }

    /**
    * @notice Get the value of an asset held in strategy. by redeempirce
     * @param _strategy Address of strategy
     * @return balance Balance of strategy usd (1e18)
     */
    function _checkValueInStrategyByRedeem(address _strategy, uint256[] memory assetDecimals, uint256[] memory assetRedeemPrices) internal view returns (uint256){
        IStrategy strategy = IStrategy(_strategy);
        (address[] memory _tokens, uint256[] memory _amounts, bool isUsd, uint256 usdValue) = strategy.getPositionDetail();
        uint256 strategyAssetValue = 0;
        if (isUsd) {
            strategyAssetValue = usdValue;
        } else {
            uint256 trackedAssetsLength = trackedAssetsMap.length();
            for (uint256 i = 0; i < _tokens.length; i++) {
                if (_amounts[i] > 0) {
                    for (uint256 j = 0; j < trackedAssetsLength; j++) {
                        (address trackedAsset,) = trackedAssetsMap.at(j);
                        if (trackedAsset == _tokens[i]) {
                            strategyAssetValue = strategyAssetValue + (_amounts[i].mulTruncateScale(assetRedeemPrices[j], 10 ** assetDecimals[j]));
                            break;
                        }
                    }
                }
            }
        }
        return strategyAssetValue;
    }

    /// @notice Change USDi supply with Vault total assets.
    function rebase() external isVaultManager defense {
        _rebase();
    }
    /**
     * @dev Calculate the total value of assets held by the Vault and all
     *      strategies and update the supply of OUSD, optionally sending a
     *      portion of the yield to the trustee.
     */
    function _rebase() internal whenNotEmergency whenNotRebasePaused {
        uint256 usdiSupply = usdi.totalSupply();
        if (usdiSupply == 0) {
            return;
        }
        uint256 vaultValue = _totalAssetInVault() + _totalAssetInStrategies();

        // Yield fee collection
        address _treasureAddress = treasury;
        // gas savings
        if (trusteeFeeBps > 0 && _treasureAddress != address(0) && (vaultValue > usdiSupply)) {
            uint256 yield = vaultValue - usdiSupply;
            uint256 fee = yield * trusteeFeeBps / 10000;
            require(yield > fee, "Fee must not be greater than yield");
            if (fee > 0) {
                usdi.mint(_treasureAddress, fee);
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
    function lend(address _strategy, IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens) external isVaultManager whenNotEmergency isActiveStrategy(_strategy) {
        (address[] memory _wants, uint[] memory _ratios) = IStrategy(_strategy).getWantsInfo();
        uint256[] memory toAmounts = new uint256[](_wants.length);
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
        //Definition rule 0 means unconstrained, currencies that do not participate are not in the returned wants
        uint256 minProductIndex = 0;
        if (_ratios.length > 1) {
            for (uint256 i = 0; i < _ratios.length; i++) {
                //                 console.log('token %s amount %d aspect %d', _wants[i], toAmounts[i], _ratios[i]);
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
        //        console.log("(minProductIndex,minAspect,minMount)", minProductIndex, minAspect, minMount);
        for (uint256 i = 0; i < toAmounts.length; i++) {
            if (toAmounts[i] > 0) {
                // console.log('token %s amount %d', _wants[i], toAmounts[i]);
                // console.log(' minProductIndex %d minMount %d minAspect %d', minProductIndex, minMount, minAspect);
                uint256 actualAmount = toAmounts[i];
                if (_ratios[i] > 0) {
                    actualAmount = _ratios[i] * minMount / minAspect;
                }
                toAmounts[i] = actualAmount;
                // console.log('token %s actual amount %d', _wants[i], actualAmount);
                IERC20Upgradeable(_wants[i]).safeTransfer(_strategy, actualAmount);
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
        emit Exchange(_fromToken, _amount, _toToken, exchangeAmount);
    }

    /// @notice redeem the funds from specified strategy.
    function redeem(address _strategy, uint256 _amount) external isKeeper isActiveStrategy(_strategy) whenNotEmergency {
        uint256[] memory _assetDecimals = _getAssetDecimals();
        uint256 strategyAssetValue = _checkBalanceInStrategy(_strategy, _assetDecimals);
        require(_amount <= strategyAssetValue);
        console.log("(amount,totalasset)",_amount,strategyAssetValue);

        IStrategy strategy = IStrategy(_strategy);
        strategy.repay(_amount, strategyAssetValue);
        // console.log('[vault.redeem] %s redeem _amount %d totalDebt %d ', _strategy, _amount, strategyAssetValue);
        emit Redeem(_strategy, _amount);
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
        if (price > 1e8) {
            price = 1e8;
        }
        // Price from Oracle is returned with 8 decimals so scale to 18
        return price.scaleBy(18, 8);
    }


    /***************************************
                     WithdrawalQueue
     ****************************************/
    function getWithdrawalQueue() external view returns (address[] memory) {
        return withdrawQueue;
    }

    function removeStrategyFromQueue(address[] memory _strategies) external isVaultManager defense {
        for (uint256 i = 0; i < _strategies.length; i++) {
            _removeStrategyFromQueue(_strategies[i]);
        }
        emit RemoveStrategyFromQueue(_strategies);
    }

    function _removeStrategyFromQueue(address _strategy) internal {
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            address curStrategy = withdrawQueue[i];
            if (curStrategy == ZERO_ADDRESS) break;
            if (curStrategy == _strategy) {
                withdrawQueue[i] = ZERO_ADDRESS;
                _organizeWithdrawalQueue();
                //                emit RemoveStrategyFromQueue(_strategy);
                return;
            }
        }
    }

    function _organizeWithdrawalQueue() internal {
        uint256 offset = 0;
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            address strategy = withdrawQueue[i];
            if (strategy == ZERO_ADDRESS) {
                offset += 1;
            } else if (offset > 0) {
                withdrawQueue[i - offset] = strategy;
                withdrawQueue[i] = ZERO_ADDRESS;
            }
        }
    }
}