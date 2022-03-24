pragma solidity ^0.8.0;
/**
 * @title  Vault Contract
 * @notice The Vault contract defines the storage for the Vault contracts
 * @author BankOfChain Protocol Inc
 */


import "./VaultStorage.sol";

contract Vault is VaultStorage {

    using SafeMath for uint256;
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

    /**
     * @dev Verifies that the rebasing is not paused.
     */
    modifier whenNotRebasePaused() {
        require(!rebasePaused, "Rebasing paused");
        _;
    }

    modifier isActiveStrategy(address _strategy) {
        require(strategySet.contains(_strategy),"strategy not exist");
        _;
    }


    function initialize(
        address _usdi,
        address _accessControlProxy,
        address _treasury,
        address _exchangeManager,
        address _valueInterpreter
    ) public initializer {
        require(_usdi != address(0), "uSDi address is zero");
        _initAccessControl(_accessControlProxy);

        treasury = _treasury;
        exchangeManager = _exchangeManager;
        valueInterpreter = _valueInterpreter;

        usdi = USDi(_usdi);

        // Initial redeem fee of 0 basis points
        redeemFeeBps = 0;
        // Threshold for rebasing
        rebaseThreshold = 1000e18;
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
        uint256 tokenLength = trackedAssetsMap.length();
        address[] memory trackedAssets = new address[](tokenLength);
        for (uint256 i = 0; i < tokenLength; i++) {
            (address trackedAddress,) = trackedAssetsMap.at(i);
            trackedAssets[i] = trackedAddress;
        }
        return trackedAssets;
    }


    /// @notice Vault holds asset value directly in USD (1e18)
    function valueOfTrackedTokens() external view returns (uint256 _totalValue){
        uint256 trackedAssetsLength = trackedAssetsMap.length();
        for (uint256 i = 0; i < trackedAssetsLength; i++) {
            (address trackedAsset,) = trackedAssetsMap.at(i);
            uint256 balance = IERC20Upgradeable(trackedAsset).balanceOf(address(this));
            if (balance > 0) {
                uint256 decimals = Helpers.getDecimals(trackedAsset);
                _totalValue = _totalValue.add(balance.scaleBy(18, decimals));
            }
        }
        console.log('[vault.valueOfTrackedTokens] end totalValue:%d', _totalValue);
    }


    /// @notice Vault total asset in USD(1e18)
    function totalAssets() external view returns (uint256){
        return _totalAssetInVault().add(_totalAssetInStrategies());
    }
    /**
    * @dev Internal to calculate total value of all assets held in Vault.
     * @return _value Total value in USD (1e18)
     */
    function _totalAssetInVault() internal view returns (uint256 _value) {
        uint256 trackedAssetsLength = trackedAssetsMap.length();
        for (uint256 i = 0; i < trackedAssetsLength; i++) {
            (address trackedAsset,) = trackedAssetsMap.at(i);
            uint256 balance = IERC20Upgradeable(trackedAsset).balanceOf(address(this));
            if (balance > 0) {
                uint256 decimals = Helpers.getDecimals(trackedAsset);
                _value = _value.add(balance.scaleBy(18, decimals));
            }
        }
    }
    /**
     * @dev Internal to calculate total value of all assets held in Strategies.
     * @return _value Total value in USD (1e18)
     */
    function _totalAssetInStrategies() internal view returns (uint256 _value) {
        uint256 strategyLength = strategySet.length();
        for (uint256 i = 0; i < strategyLength; i++) {
            IStrategy strategy = IStrategy(strategySet.at(i));
            (address[] memory _tokens, uint256[] memory _amounts) = strategy.getPositionDetail();
            for (uint256 j = 0; j < _tokens.length; j++) {
                if (_amounts[j] > 0) {
                    uint256 decimals = Helpers.getDecimals(_tokens[j]);
                    _value = _value.add(_amounts[j].scaleBy(18, decimals));
                }
            }
        }
    }


    /// @notice All strategies
    function getStrategies() external view returns (address[] memory _strategies){
        return strategySet.values();
    }

    /// @notice Added support for specific asset.
    function addAsset(address _asset) external isVaultManager whenNotEmergency {
        require(!assetSet.contains(_asset), "Asset already supported");
        assetSet.add(_asset);
        // Verify that our oracle supports the asset
        // slither-disable-next-line unused-return
        IValueInterpreter(valueInterpreter).price(_asset);
        trackedAssetsMap.plus(_asset, 1);
        emit AddAsset(_asset);
    }

    /// @notice Remove support for specific asset.
    function removeAsset(address _asset) external isVaultManager whenNotEmergency {
        require(assetSet.contains(_asset), "Asset already not supported");
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
    function addStrategy(address[] memory _strategies) external isVaultManager whenNotEmergency {
        bool addressValid = true;
        bool strategyNotExit = true;
        bool vaultValid = true;
        for (uint256 i = 0; i < _strategies.length; i++) {
            addressValid = (_strategies[i] != ZERO_ADDRESS);
            if (addressValid == false) {
                break;
            }
            strategyNotExit = !strategySet.contains(_strategies[i]);
            if (strategyNotExit == false) {
                break;
            }
            vaultValid = (IStrategy(_strategies[i]).vault() == address(this));
            if (vaultValid == false) {
                break;
            }
        }
        require(addressValid && strategyNotExit && vaultValid, "Strategy is invalid or the strategy already existed or vault address invalid");


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
    function removeStrategy(address[] memory _strategies) external isVaultManager {
        for (uint256 i = 0; i < _strategies.length; i++) {
            _removeStrategy(_strategies[i]);
        }
        emit RemoveStrategies(_strategies);
    }

    /**
    * @dev Remove a strategy from the Vault.
     * @param _addr Address of the strategy to remove
     */
    function _removeStrategy(address _addr) internal {
        require(strategySet.contains(_addr), "Strategy not exist");

        // Withdraw all assets
        IStrategy strategy = IStrategy(_addr);

        strategy.repay(MAX_BPS, MAX_BPS);

        address[] memory _wants = strategy.getWants();
        for (uint i = 0; i < _wants.length; i++) {
            address wantToken = _wants[i];
            trackedAssetsMap.minus(wantToken, 1);
            if (trackedAssetsMap.get(wantToken) <= 0 && IERC20Upgradeable(wantToken).balanceOf(address(this)) == 0) {
                trackedAssetsMap.remove(wantToken);
            }
        }

        _removeStrategyFromQueue(_addr);
    }

    /// @notice Minting USDi with stablecoins
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @dev Support single asset or multi-assets
    function mint(address[] memory _assets, uint256[] memory _amounts) external whenNotEmergency defense {
        require(_assets.length > 0 && _amounts.length > 0 && _assets.length == _amounts.length, "Assets or amounts must not be empty and Assets length equal amounts");
        bool amountsGreaterThanZero = true;
        bool assetsExist = true;

        for (uint256 i = 0; i < _assets.length; i++) {
            assetsExist = trackedAssetsMap.contains(_assets[i]);
            if (assetsExist == false) {
                break;
            }
            amountsGreaterThanZero = (_amounts[i] > 0);
            if (amountsGreaterThanZero == false) {
                break;
            }
        }
        require(assetsExist, "Asset is not supported");
        require(amountsGreaterThanZero, "Amount must be greater than 0");
        uint256 unitAdjustedDeposit = 0;
        uint256 priceAdjustedDeposit = 0;
        for (uint256 i = 0; i < _assets.length; i++) {
            uint256 price = _priceUSDMint(_assets[i]);
            uint256 assetDecimals = Helpers.getDecimals(_assets[i]);
            // Scale up to 18 decimal
            unitAdjustedDeposit = unitAdjustedDeposit.add(_amounts[i].scaleBy(18, assetDecimals));
            priceAdjustedDeposit = priceAdjustedDeposit.add(_amounts[i].mulTruncateScale(price, 10 ** assetDecimals));
        }

        //        if (_minimumUsdiAmount > 0) {
        //            require(
        //                priceAdjustedDeposit >= _minimumUsdiAmount,
        //                "Mint amount lower than minimum"
        //            );
        //        }

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
        //        if (unitAdjustedDeposit >= autoAllocateThreshold) {
        //            _allocate();
        //        }
        emit Mint(msg.sender, _assets, _amounts, priceAdjustedDeposit);
    }

    /// @notice burn USDi,return stablecoins
    /// @param _amount Amount of USDi to burn
    /// @param _asset one of StableCoin asset
    function burn(uint256 _amount,
        address _asset,
        uint256 _minimumUnitAmount,
        IExchangeAggregator.ExchangeToken[] memory _exchangeTokens
    ) external whenNotEmergency whenNotRebasePaused defense {
        require(_amount > 0 && _amount <= usdi.balanceOf(msg.sender), "Amount must be greater than 0 and less than or equal to balance");
        require(assetSet.contains(_asset), "The asset not support");
        bool toTokenValid = true;
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            toTokenValid = _exchangeTokens[i].toToken == _asset;
            if (toTokenValid == false) {
                break;
            }
        }
        require(toTokenValid, "toToken is invalid");

        uint256 _burnAmount = _amount;
        // Calculate redeem fee
        if (redeemFeeBps > 0) {
            _burnAmount = _burnAmount.sub(_amount.mul(redeemFeeBps).div(10000));
        }
        //redeem price in vault
        uint256 _totalValueInVault = _calculateValueInVault();
        // vault not enough
        if (_totalValueInVault < _burnAmount) {
            _repayFromWithdrawQueue(_burnAmount - _totalValueInVault);
        }

        uint256[] memory outputs = _calculateOutput(_burnAmount);

        _checkUSDIBackedEnough();

        uint256 _actualAmount = 0;
        for (uint256 i = 0; i < trackedAssetsMap.length(); i++) {
            (address withdrawToken,) = trackedAssetsMap.at(i);
            uint256 withdrawDecimals = Helpers.getDecimals(withdrawToken);
            uint256 withdrawAmount = outputs[i].scaleBy(withdrawDecimals, 18);
            if (withdrawAmount > 0) {
                if (withdrawToken == _asset) {
                    _actualAmount = _actualAmount.add(outputs[i]);
                } else {
                    for (uint256 j = 0; j < _exchangeTokens.length; j++) {
                        IExchangeAggregator.ExchangeToken memory exchangeToken = _exchangeTokens[j];
                        if (exchangeToken.fromToken == withdrawToken) {
                            uint256 toDecimals = Helpers.getDecimals(exchangeToken.toToken);
                            uint256 toAmount = _exchange(exchangeToken.fromToken, exchangeToken.toToken, withdrawAmount, exchangeToken.exchangeParam);
                            console.log('withdraw exchange token %s amount %d toAmount %d', withdrawAmount, withdrawAmount, toAmount);
                            _actualAmount = _actualAmount.add(toAmount.scaleBy(18, toDecimals));
                            break;
                        }
                    }
                }
            }
        }

        uint256 assetDecimals = Helpers.getDecimals(_asset);
        _actualAmount = _actualAmount.scaleBy(assetDecimals, 18);

        if (IERC20Upgradeable(_asset).balanceOf(address(this)) >= _actualAmount) {
            // Use Vault funds first if sufficient
            IERC20Upgradeable(_asset).safeTransfer(msg.sender, _actualAmount);
        } else {
            revert("Liquidity error");
        }

        if (_minimumUnitAmount > 0) {
            require(
                _actualAmount >= _minimumUnitAmount,
                "Redeem amount lower than minimum"
            );
        }

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

    // calculate Value In Vault by priceUSDRedeem usd (1e18)
    function _calculateValueInVault() internal returns (uint256 _totalValueInVault){
        //redeem price in vault
        uint256 trackedAssetsLength = trackedAssetsMap.length();
        for (uint256 i = 0; i < trackedAssetsLength; i++) {
            (address trackedAsset,) = trackedAssetsMap.at(i);
            uint256 balance = IERC20Upgradeable(trackedAsset).balanceOf(address(this));
            if (balance > 0) {
                uint256 decimals = Helpers.getDecimals(trackedAsset);
                uint256 price = _priceUSDRedeem(trackedAsset);
                _totalValueInVault = _totalValueInVault.add(balance.mulTruncateScale(price, 10 ** decimals));
            }
        }
    }

    // withdraw from strategy queue
    function _repayFromWithdrawQueue(uint256 needWithdrawValue) internal {
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            address _strategy = withdrawQueue[i];
            if (_strategy == ZERO_ADDRESS) break;

            if (!strategySet.contains(_strategy)) {
                continue;
            }
            uint256 strategyTotalValue = 0;
            IStrategy strategy = IStrategy(_strategy);
            (address[] memory _tokens, uint256[] memory _amounts) = strategy.getPositionDetail();
            for (uint256 i = 0; i < _tokens.length; i++) {
                if (_amounts[i] > 0) {
                    uint256 decimals = Helpers.getDecimals(_tokens[i]);
                    uint256 price = _priceUSDRedeem(_tokens[i]);
                    strategyTotalValue = strategyTotalValue.add(_amounts[i].mulTruncateScale(price, 10 ** decimals));
                }
            }

            uint256 strategyWithdrawValue;
            if (needWithdrawValue > strategyTotalValue) {
                strategyWithdrawValue = strategyTotalValue;
                needWithdrawValue -= strategyWithdrawValue;
            } else {
                strategyWithdrawValue = needWithdrawValue;
                needWithdrawValue = 0;
            }
            console.log('start withdrawn from %s numerator %d denominator %d', strategy.name(), strategyWithdrawValue, strategyTotalValue);
            (address[] memory withdrawStrategyAssets, uint256[] memory withdrawStrategyAmounts) = strategy.repay(strategyWithdrawValue, strategyTotalValue);

            if (needWithdrawValue <= 0) {
                break;
            }
        }
    }

    function _calculateOutput(uint256 _needTransferAmount) internal returns (uint256[] memory){
        uint256 trackedAssetsMapLength = trackedAssetsMap.length();
        uint256[] memory outputs = new uint256[](trackedAssetsMapLength);
        for (uint256 i = 0; i < trackedAssetsMapLength; i++) {
            (address trackedAsset,) = trackedAssetsMap.at(i);
            uint256 balance = IERC20Upgradeable(trackedAsset).balanceOf(address(this));
            uint256 decimals = Helpers.getDecimals(trackedAsset);
            if (balance > 0) {
                uint256 price = _priceUSDRedeem(trackedAsset);
                uint256 _value = balance.mulTruncateScale(price, 10 ** decimals);
                if (_value >= _needTransferAmount) {
                    outputs[i] = _needTransferAmount;
                    break;
                } else {
                    outputs[i] = _value;
                    _needTransferAmount = _needTransferAmount.sub(_value);
                }
            }
        }
    }

    //Check that USDI is backed by enough assets
    function _checkUSDIBackedEnough() internal {
        if (maxSupplyDiff > 0) {
            // Check that USDI is backed by enough assets
            uint256 _totalSupply = usdi.totalSupply();
            uint256 _backingValue = _totalAssetInVault().add(_totalAssetInStrategies());
            // Allow a max difference of maxSupplyDiff% between
            // backing assets value and OUSD total supply
            uint256 diff = _totalSupply.divPrecisely(_backingValue);
            require(
                (diff > 1e18 ? diff.sub(1e18) : uint256(1e18).sub(diff)) <=
                maxSupplyDiff,
                "Backing supply liquidity error"
            );
        }
    }

    /// @notice burn USDi,return stablecoins without exchange
    /// @param _amount Amount of USDi to burn
    function burnWithoutExchange(uint256 _amount,
        uint256 _minimumUnitAmount
    ) external returns (address[] memory _assets, uint256[] memory _amounts){
        require(_amount > 0 && _amount <= usdi.balanceOf(msg.sender), "Amount must be greater than 0 and less than or equal to balance");

        uint256 _burnAmount = _amount;
        // Calculate redeem fee
        if (redeemFeeBps > 0) {
            _burnAmount = _burnAmount.sub(_amount.mul(redeemFeeBps).div(10000));
        }
        //redeem price in vault
        uint256 _totalValueInVault = _calculateValueInVault();
        // vault not enough
        if (_totalValueInVault < _burnAmount) {
            _repayFromWithdrawQueue(_burnAmount - _totalValueInVault);
        }

        uint256[] memory outputs = _calculateOutput(_burnAmount);

        _checkUSDIBackedEnough();

        uint256 _actualAmount = 0;
        for (uint256 i = 0; i < trackedAssetsMap.length(); i++) {
            _actualAmount = _actualAmount.add(outputs[i]);
            (address withdrawToken,) = trackedAssetsMap.at(i);
            uint256 withdrawDecimals = Helpers.getDecimals(withdrawToken);
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

        if (_minimumUnitAmount > 0) {
            require(
                _actualAmount >= _minimumUnitAmount,
                "Redeem amount lower than minimum"
            );
        }

        usdi.burn(msg.sender, _burnAmount);

        // Until we can prove that we won't affect the prices of our assets
        // by withdrawing them, this should be here.
        // It's possible that a strategy was off on its asset total, perhaps
        // a reward token sold for more or for less than anticipated.
        if (_burnAmount > rebaseThreshold && !rebasePaused) {
            _rebase();
        }
        address[] memory _assets = _getTrackedAssets();
        emit BurnWithoutExchange(msg.sender, _assets, outputs, _burnAmount);
        return (_assets, outputs);
    }

    /// @notice Change USDi supply with Vault total assets.
    function rebase() external isVaultManager whenNotEmergency whenNotRebasePaused {
        _rebase();
    }
    /**
     * @dev Calculate the total value of assets held by the Vault and all
     *      strategies and update the supply of OUSD, optionally sending a
     *      portion of the yield to the trustee.
     */
    function _rebase() internal {
        uint256 usdiSupply = usdi.totalSupply();
        if (usdiSupply == 0) {
            return;
        }
        uint256 vaultValue = _totalAssetInVault().add(_totalAssetInStrategies());

        // Yield fee collection
        address _treasureAddress = treasury;
        // gas savings
        if (_treasureAddress != address(0) && (vaultValue > usdiSupply)) {
            uint256 yield = vaultValue.sub(usdiSupply);
            uint256 fee = yield.mul(trusteeFeeBps).div(10000);
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
    /**
     * @dev Sets the TrusteeFeeBps to the percentage of yield that should be
     *      received in basis points.
     */
    function setTrusteeFeeBps(uint256 _basis) external isVaultManager {
        require(_basis <= 5000, "basis cannot exceed 50%");
        trusteeFeeBps = _basis;
    }

    /// @notice Allocate funds in Vault to strategies.
    function lend(address _strategy, IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens) external isVaultManager whenNotEmergency isActiveStrategy(_strategy) {
        (address[] memory _wants,uint[] memory _ratios) = IStrategy(_strategy).getWantsInfo();
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
        //定义规则 0 表示不受约束，不参与的币种不在返回wants里
        uint256 minProductIndex = 0;
        if (_ratios.length > 1) {
            for (uint256 i = 0; i < _ratios.length; i++) {
                console.log('token %s amount %d aspect %d', _wants[i], toAmounts[i], _ratios[i]);
                // console.log('token i+1  %s amount %d aspect %d', tokenDetails[i + 1].token, tokenDetails[i + 1].amount, tokenAspects[i + 1].aspect);
                if (_ratios[i] == 0) {
                    //允许wants中存在占比为0的token
                    continue;
                } else if (minProductIndex == 0) {
                    //minProductIndex赋值给第一个占比不为0的index
                    minProductIndex = i;
                } else if (toAmounts[minProductIndex] * _ratios[i] > toAmounts[i] * _ratios[minProductIndex]) {
                    minProductIndex = i;
                }
            }
        }

        uint256 minMount = toAmounts[minProductIndex];
        uint256 minAspect = _ratios[minProductIndex];
        for (uint256 i = 0; i < toAmounts.length; i++) {
            if (toAmounts[i] > 0) {
                console.log('token %s amount %d', _wants[i], toAmounts[i]);
                console.log(' minProductIndex %d minMount %d minAspect %d', minProductIndex, minMount, minAspect);
                uint256 actualAmount = toAmounts[i];
                if (_ratios[i] > 0) {
                    actualAmount = _ratios[i] * minMount / minAspect;
                }
                toAmounts[i] = actualAmount;
                console.log('token %s actual amount %d', _wants[i], actualAmount);
                IERC20Upgradeable(_wants[i]).safeTransfer(_strategy, actualAmount);
            }
        }
    }

    function _exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory exchangeParam
    ) internal returns (uint256 exchangeAmount) {
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
        //        emit Exchange(_fromToken, _amount, _toToken, exchangeAmount);
    }

    /// @notice redeem the funds from specified strategy.
    function redeem(address _strategy, uint256 _amount) external isKeeper isActiveStrategy(_strategy) whenNotEmergency {
        IStrategy strategy = IStrategy(_strategy);
        //需要注意8位还是18位，确认后调整
        uint256 strategyAssetValue = strategy.estimatedTotalAssets();
        require(_amount <= strategyAssetValue);
        (address[] memory _assets, uint256[] memory _amounts) = strategy.repay(_amount, strategyAssetValue);
        uint256 redeemValue;
        for (uint256 j = 0; j < _assets.length; j++) {
            uint256 decimals = Helpers.getDecimals(_assets[j]);
            uint256 price = _priceUSDRedeem(_assets[j]);
            redeemValue = redeemValue.add(_amounts[j].mulTruncateScale(price, 10 ** decimals));
        }

        console.log('[vault.redeem] %s redeem _amount %d totalDebt %d ', strategy.name(), _amount, strategyAssetValue);
        emit Redeem(_strategy, _amount);
    }

    /// @notice Shutdown the vault when an emergency occurs, cannot mint/burn.
    function setEmergencyShutdown(bool active) external isVaultManager {
        emergencyShutdown = active;
        emit SetEmergencyShutdown(active);
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

    /**
     * @dev Returns the total price in 18 digit USD for a given asset.
     *      Never goes below 1, since that is how we price redeems
     * @param asset Address of the asset
     * @return uint256 USD price of 1 of the asset, in 18 decimal fixed
     */
    function _priceUSDRedeem(address asset) internal view returns (uint256) {
        uint256 price = IValueInterpreter(valueInterpreter).price(asset);
        if (price < 1e8) {
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

    function setWithdrawalQueue(address[] memory queue) external isKeeper {
        bool strategyExist = true;
        for (uint256 i = 0; i < queue.length; i++) {
            strategyExist = strategySet.contains(queue[i]);
            if (strategyExist == false) {
                break;
            }
        }
        require(strategyExist, 'strategy not exist');
        for (uint256 i = 0; i < queue.length; i++) {
            address strategy = queue[i];
            if (i < withdrawQueue.length) {
                withdrawQueue[i] = strategy;
            } else {
                withdrawQueue.push(strategy);
            }
        }
        for (uint256 i = queue.length; i < withdrawQueue.length; i++) {
            if (withdrawQueue[i] == ZERO_ADDRESS) break;
            withdrawQueue[i] = ZERO_ADDRESS;
        }
        //        emit SetWithdrawalQueue(queue);
    }

    function removeStrategyFromQueue(address[] memory _strategies) external isVaultManager {
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