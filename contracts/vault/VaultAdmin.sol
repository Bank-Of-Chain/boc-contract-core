// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./VaultStorage.sol";

/// @title USDI/ETHi Vault Admin Contract
/// @notice The VaultAdmin contract makes configuration and admin calls on the vault.
/// @author Bank of Chain Protocol Inc
contract VaultAdmin is VaultStorage {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using IterableIntMap for IterableIntMap.AddressToIntMap;

    modifier isActiveStrategy(address _strategy) {
        checkActiveStrategy(_strategy);
        _;
    }

    modifier whenNonEmergency() {
        require(!emergencyShutdown, "ES"); //emergency shutdown
        _;
    }

    /// @notice Check '_strategy' is active or not
    function checkActiveStrategy(address _strategy) public view {
        require(strategySet.contains(_strategy), "NE"); //not exist
    }

    // External functions

    /// @dev Shutdown the vault when an emergency occurs, cannot mint/burn.
    /// Requirements: only vault manager can call
    function setEmergencyShutdown(bool _active) external isVaultManager {
        emergencyShutdown = _active;
        emit SetEmergencyShutdown(_active);
    }

    /// @dev Sets adjustPositionPeriod true when adjust position occurs,
    ///   cannot remove add asset/strategy and cannot mint/burn.
    /// Requirements: only keeper can call
    function setAdjustPositionPeriod(bool _adjustPositionPeriod) external isKeeperOrVaultOrGovOrDelegate {
        adjustPositionPeriod = _adjustPositionPeriod;
        emit SetAdjustPositionPeriod(_adjustPositionPeriod);
    }

    /// @dev Sets a minimum difference ratio automatically rebase.
    /// @param _threshold _threshold is the numerator and the denominator is 1e7. x/1e7
    /// Requirements: only vault manager can call
    function setRebaseThreshold(uint256 _threshold) external isVaultManager {
        rebaseThreshold = _threshold;
        emit RebaseThresholdUpdated(_threshold);
    }

    /// @dev Sets a max reduce difference ratio when will revert(when lend or redeem)
    /// @param _threshold _threshold is the numerator and the denominator is 1e7. x/1e7
    /// Requirements: only vault manager can call
    function setDeltaThreshold(uint256 _threshold) external isVaultManager {
        deltaThreshold = _threshold;
        emit DeltaThresholdUpdated(_threshold);
    }

    /// @dev Sets a fee in basis points to be charged for a redeem.
    /// @param _redeemFeeBps Basis point fee to be charged
    /// Requirements: only vault manager can call
    function setRedeemFeeBps(uint256 _redeemFeeBps) external isVaultManager {
        require(_redeemFeeBps <= 1000, "Redeem fee should not be over 10%");
        redeemFeeBps = _redeemFeeBps;
        emit RedeemFeeUpdated(_redeemFeeBps);
    }

    /// @dev Sets the Maximum timestamp between two reported
    /// Requirements: only vault manager can call
    function setMaxTimestampBetweenTwoReported(
        uint256 _maxTimestampBetweenTwoReported
    ) external isVaultManager {
        maxTimestampBetweenTwoReported = _maxTimestampBetweenTwoReported;
        emit MaxTimestampBetweenTwoReportedChanged(_maxTimestampBetweenTwoReported);
    }

    /// @dev Sets the minimum strategy total debt that will be checked for the strategy reporting
    /// Requirements: only vault manager can call
    function setMinCheckedStrategyTotalDebt(
        uint256 _minCheckedStrategyTotalDebt
    ) external isVaultManager {
        minCheckedStrategyTotalDebt = _minCheckedStrategyTotalDebt;
        emit MinCheckedStrategyTotalDebtChanged(_minCheckedStrategyTotalDebt);
    }

    /// @dev Sets Minimum Investment Amount
    /// Requirements: only vault manager can call
    function setMinimumInvestmentAmount(uint256 _minimumInvestmentAmount) external isVaultManager {
        minimumInvestmentAmount = _minimumInvestmentAmount;
        emit MinimumInvestmentAmountChanged(_minimumInvestmentAmount);
    }

    /// @dev Sets the treasuryAddress that can receive a portion of yield.
    ///      Setting to the zero address disables this feature.
    /// Requirements: only governance role can call
    function setTreasuryAddress(address _address) external onlyRole(BocRoles.GOV_ROLE) {
        //The error message "NNA" represents "The input address need be non-zero address"
        require(_address != address(0), "NNA");
        treasury = _address;
        emit TreasuryAddressChanged(_address);
    }

    /// @dev Sets the exchangeManagerAddress that can receive a portion of yield.
    /// Requirements: only governance role can call
    function setExchangeManagerAddress(
        address _exchangeManagerAddress
    ) external onlyRole(BocRoles.GOV_ROLE) {
        require(_exchangeManagerAddress != address(0), "exchangeManager ad is 0");
        exchangeManager = _exchangeManagerAddress;
        emit ExchangeManagerAddressChanged(_exchangeManagerAddress);
    }

    /// @dev Sets `_address` to `vaultBufferAddress`
    /// Requirements: only governance role can call
    function setVaultBufferAddress(address _address) external onlyRole(BocRoles.GOV_ROLE) {
        require(_address != address(0), "vaultBuffer ad is 0");
        require(vaultBufferAddress == address(0), "VaultBuffer ad has been set");
        vaultBufferAddress = _address;
    }

    /// @dev Sets `_address` to `pegTokenAddress`
    /// Requirements: only governance role can call
    function setPegTokenAddress(address _address) external onlyRole(BocRoles.GOV_ROLE) {
        require(_address != address(0), "PegToken ad is 0");
        require(pegTokenAddress == address(0), "PegToken ad has been set");
        pegTokenAddress = _address;
    }

    /// @dev Sets the TrusteeFeeBps to the percentage of yield that should be
    ///      received in basis points.
    /// Requirements: only vault manager can call
    function setTrusteeFeeBps(uint256 _basis) external isVaultManager {
        require(_basis <= 5000, "basis cannot exceed 50%");
        trusteeFeeBps = _basis;
        emit TrusteeFeeBpsChanged(_basis);
    }

    /// @dev Sets '_enabled' to the 'enforceChangeLimit' field of '_strategy'
    /// Requirements: only vault manager can call
    function setStrategyEnforceChangeLimit(address _strategy, bool _enabled) external isVaultManager {
        strategies[_strategy].enforceChangeLimit = _enabled;
    }

    /// @dev Sets '_lossRatioLimit' to the 'lossRatioLimit' field of '_strategy'
    ///      Sets '_profitLimitRatio' to the 'profitLimitRatio' field of '_strategy'
    /// Requirements: only vault manager can call
    function setStrategySetLimitRatio(
        address _strategy,
        uint256 _lossRatioLimit,
        uint256 _profitLimitRatio
    ) external isVaultManager {
        strategies[_strategy].lossLimitRatio = _lossRatioLimit;
        strategies[_strategy].profitLimitRatio = _profitLimitRatio;
    }

    /// @dev Sets the deposit paused flag to true to prevent rebasing.
    /// Requirements: only vault manager can call
    function pauseRebase() external isVaultManager {
        rebasePaused = true;
        emit RebasePaused();
    }

    /// @dev Sets the deposit paused flag to true to allow rebasing.
    /// Requirements: only vault manager can call
    function unpauseRebase() external isVaultManager {
        rebasePaused = false;
        emit RebaseUnpaused();
    }

    /// @dev Added support for specific asset.
    /// Requirements: only vault manager can call
    function addAsset(address _asset) external isVaultManager {
        require(!assetSet.contains(_asset), "existed");
        // slither-disable-next-line unused-return
        assetSet.add(_asset);
        // Verify that our oracle supports the asset
        // slither-disable-next-line uninitialized-state
        if (vaultType > 0) {
            if (_asset != NativeToken.NATIVE_TOKEN) {
                // slither-disable-next-line uninitialized-state
                IValueInterpreter(valueInterpreter).priceInEth(_asset);
            }
        } else {
            // slither-disable-next-line uninitialized-state
            IValueInterpreter(valueInterpreter).price(_asset);
        }
        trackedAssetsMap.plus(_asset, 1);
        trackedAssetDecimalsMap[_asset] = _getDecimals(_asset);
        emit AddAsset(_asset);
    }

    /// @dev Remove support for specific asset.
    /// Requirements: only vault manager can call
    function removeAsset(address _asset) external isVaultManager {
        address _vaultBufferAddress = vaultBufferAddress;
        require(assetSet.contains(_asset), "not exist");
        require(balanceOfTokenByOwner(_asset, _vaultBufferAddress) < 10, "vaultBuffer exist this asset");
        assetSet.remove(_asset);
        trackedAssetsMap.minus(_asset, 1);
        if (
            trackedAssetsMap.get(_asset) <= 0 &&
            balanceOfTokenByOwner(_asset, address(this)) < 1 &&
            balanceOfTokenByOwner(_asset, _vaultBufferAddress) < 1
        ) {
            // slither-disable-next-line unused-return
            trackedAssetsMap.remove(_asset);
            delete trackedAssetDecimalsMap[_asset];
        }
        emit RemoveAsset(_asset);
    }

    /// @notice Add strategy to strategy list
    /// @dev The strategy added to the strategy list,
    ///      Vault may invest funds into the strategy,
    ///      and the strategy will invest the funds in the 3rd protocol
    /// Requirements: only vault manager can call
    function addStrategies(StrategyAdd[] memory _strategyAdds) external isVaultManager {
        address[] memory _strategies = new address[](_strategyAdds.length);
        for (uint256 i = 0; i < _strategyAdds.length; i++) {
            StrategyAdd memory _strategyAdd = _strategyAdds[i];
            address _strategyAddr = _strategyAdd.strategy;
            require(
                (_strategyAddr != ZERO_ADDRESS) &&
                    (!strategySet.contains(_strategyAddr)) &&
                    (address(IStrategy(_strategyAddr).vault()) == address(this)),
                "Strategy is invalid"
            );
            _strategies[i] = _strategyAddr;
            _addStrategy(
                _strategyAddr,
                _strategyAdd.profitLimitRatio,
                _strategyAdd.lossLimitRatio,
                _strategyAdd.targetDebt
            );
            address[] memory _wants = IStrategy(_strategyAddr).getWants();
            for (uint256 j = 0; j < _wants.length; j++) {
                trackedAssetsMap.plus(_wants[j], 1);
                if (trackedAssetDecimalsMap[_wants[j]] == 0) {
                    trackedAssetDecimalsMap[_wants[j]] = _getDecimals(_wants[j]);
                }
            }
        }

        emit AddStrategies(_strategies);
    }

    /// @notice Return the `withdrawQueue`
    function getWithdrawalQueue() external view returns (address[] memory) {
        return withdrawQueue;
    }

    /// @dev Sets `withdrawQueue` and add `_queues` to the front of the `withdrawQueue`
    /// @param _queues The advance queue
    /// Requirements: only keeper can call
    function setWithdrawalQueue(address[] memory _queues) external isKeeperOrVaultOrGovOrDelegate {
        for (uint256 i = 0; i < _queues.length; i++) {
            address _strategy = _queues[i];
            require(strategySet.contains(_strategy), "strategy not exist");
            if (i < withdrawQueue.length) {
                withdrawQueue[i] = _strategy;
            } else {
                withdrawQueue.push(_strategy);
            }
        }
        for (uint256 i = _queues.length; i < withdrawQueue.length; i++) {
            if (withdrawQueue[i] == ZERO_ADDRESS) break;
            withdrawQueue[i] = ZERO_ADDRESS;
        }
        emit SetWithdrawalQueue(_queues);
    }

    /// @dev Remove multi strategies from the withdrawal queue
    /// @param _strategies multi strategies to remove
    /// Requirements: only keeper can call
    function removeStrategyFromQueue(
        address[] memory _strategies
    ) external isKeeperOrVaultOrGovOrDelegate {
        for (uint256 i = 0; i < _strategies.length; i++) {
            _removeStrategyFromQueue(_strategies[i]);
        }
        emit RemoveStrategyFromQueue(_strategies);
    }

    /// @notice Remove multi strategies from strategy list
    /// @dev The removed policy withdraws funds from the 3rd protocol and returns to the Vault
    /// @param _strategies The address list of strategies to remove
    /// Requirements: only vault manager can call
    function removeStrategies(address[] memory _strategies) external isVaultManager {
        for (uint256 i = 0; i < _strategies.length; i++) {
            require(strategySet.contains(_strategies[i]), "Strategy not exist");
            _removeStrategy(_strategies[i], false);
        }
        emit RemoveStrategies(_strategies);
    }

    /// @dev Forced to remove the '_strategy'
    /// Requirements: only governance or delegate role can call
    function forceRemoveStrategy(address _strategy) external onlyGovOrDelegate {
        _removeStrategy(_strategy, true);
        emit RemoveStrategyByForce(_strategy);
    }

    // Internal functions

    function _addStrategy(
        address _strategy,
        uint256 _profitLimitRatio,
        uint256 _lossLimitRatio,
        uint256 _targetDebt
    ) internal {
        //Add strategy to approved strategies
        strategies[_strategy] = StrategyParams({
            lastReport: block.timestamp,
            totalDebt: 0,
            profitLimitRatio: _profitLimitRatio,
            lossLimitRatio: _lossLimitRatio,
            enforceChangeLimit: true,
            lastClaim: block.timestamp,
            targetDebt: _targetDebt
        });
        // slither-disable-next-line unused-return
        strategySet.add(_strategy);
    }

    /// @dev Remove a strategy from the Vault.
    /// @param _addr Address of the strategy to remove
    /// @param _force Forced to remove if 'true'
    function _removeStrategy(address _addr, bool _force) internal {
        if (strategies[_addr].totalDebt > 0) {
            // Withdraw all assets
            try IStrategy(_addr).repay(MAX_BPS, MAX_BPS, 0) {} catch {
                if (!_force) {
                    revert();
                }
            }
        }

        address[] memory _wants = IStrategy(_addr).getWants();
        address _vaultBufferAddress = vaultBufferAddress;
        for (uint256 i = 0; i < _wants.length; i++) {
            address _wantToken = _wants[i];
            trackedAssetsMap.minus(_wantToken, 1);
            if (
                trackedAssetsMap.get(_wantToken) <= 0 &&
                balanceOfTokenByOwner(_wantToken, address(this)) <= 1 &&
                balanceOfTokenByOwner(_wantToken, _vaultBufferAddress) <= 1
            ) {
                // slither-disable-next-line unused-return
                trackedAssetsMap.remove(_wantToken);
            }
        }
        if (strategies[_addr].totalDebt > 0) {
            // slither-disable-next-line costly-loop
            totalDebt -= strategies[_addr].totalDebt;
        }
        delete strategies[_addr];
        // slither-disable-next-line unused-return
        strategySet.remove(_addr);
        _removeStrategyFromQueue(_addr);
    }

    function _removeStrategyFromQueue(address _strategy) internal {
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            address _curStrategy = withdrawQueue[i];
            if (_curStrategy == ZERO_ADDRESS) break;
            if (_curStrategy == _strategy) {
                withdrawQueue[i] = ZERO_ADDRESS;
                _organizeWithdrawalQueue();

                return;
            }
        }
    }

    function _organizeWithdrawalQueue() internal {
        // slither-disable-next-line uninitialized-local
        uint256 _offset;
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            address _strategy = withdrawQueue[i];
            if (_strategy == ZERO_ADDRESS) {
                _offset += 1;
            } else if (_offset > 0) {
                withdrawQueue[i - _offset] = _strategy;
                withdrawQueue[i] = ZERO_ADDRESS;
            }
        }
    }

    function setStrategyTargetDebts(
        address[] memory _strategies,
        uint256[] memory _newTargetDebts
    ) external isKeeperOrVaultOrGovOrDelegate {
        require(_strategies.length == _newTargetDebts.length, "Two lengths must be equal");
        uint256 _len = _strategies.length;
        for (uint256 i = 0; i < _len; i++) {
            StrategyParams storage strategyParams = strategies[_strategies[i]];
            strategyParams.targetDebt = _newTargetDebts[i];
        }
    }

    function increaseStrategyTargetDebts(
        address[] memory _strategies,
        uint256[] memory _addAmounts
    ) external isKeeperOrVaultOrGovOrDelegate {
        require(_strategies.length == _addAmounts.length, "Two lengths must be equal");
        uint256 _len = _strategies.length;
        for (uint256 i = 0; i < _len; i++) {
            StrategyParams storage strategyParams = strategies[_strategies[i]];
            strategyParams.targetDebt += _addAmounts[i];
        }
    }

    /// @notice Fetch the `decimals()` from an ERC20 token
    /// @dev Grabs the `decimals()` from a contract and fails if
    ///     the decimal value does not live within a certain range
    /// @param _token Address of the ERC20 token
    /// @return uint256 Decimals of the ERC20 token
    function _getDecimals(address _token) private view returns (uint256) {
        uint256 _decimals;
        if (_token == NativeToken.NATIVE_TOKEN) {
            _decimals = 18;
        } else {
            _decimals = IERC20Metadata(_token).decimals();
        }
        require(_decimals > 0, "Token must have sufficient decimal places");
        return _decimals;
    }

    /// @notice Return the token's balance Of this contract
    function balanceOfTokenByOwner(
        address _tokenAddress,
        address _owner
    ) internal view returns (uint256) {
        if (_tokenAddress == NativeToken.NATIVE_TOKEN) {
            return _owner.balance;
        }
        return IERC20Upgradeable(_tokenAddress).balanceOf(_owner);
    }

    /// @notice Redeem the funds from specified strategy.
    /// @param  _strategy The specified strategy to redeem
    /// @param _amount The amount to redeem in USD
    /// @param _outputCode The code of output
    function redeem(
        address _strategy,
        uint256 _amount,
        uint256 _outputCode
    )
        external
        isKeeperOrVaultOrGovOrDelegate
        isActiveStrategy(_strategy)
        nonReentrant
        returns (address[] memory _assets, uint256[] memory _amounts)
    {
        uint256 _strategyAssetValue = strategies[_strategy].totalDebt;
        require(_amount <= _strategyAssetValue, "AI"); //amount invalid

        (_assets, _amounts) = IStrategy(_strategy).repay(_amount, _strategyAssetValue, _outputCode);
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
    /// @param _strategy The specified strategy to lend
    /// @param _tokens want tokens
    /// @param _amounts the amount of each tokens
    /// @param _minDeltaAssets the minimum allowable asset increment
    /// @return _deltaAssets The amount of newly added assets
    function lend(
        address _strategy,
        address[] memory _tokens,
        uint256[] memory _amounts,
        uint256 _minDeltaAssets
    )
        external
        isKeeperOrVaultOrGovOrDelegate
        whenNonEmergency
        isActiveStrategy(_strategy)
        nonReentrant
        returns (uint256 _deltaAssets)
    {
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
        // slither-disable-next-line uninitialized-local
        uint256 _lendValue;
        // slither-disable-next-line uninitialized-local
        uint256 _ethAmount;
        {
            uint256 _vaultType = vaultType;
            uint256 _minAmount = _amountsLocal[_minProductIndex];
            uint256 _minAspect = _ratios[_minProductIndex];
            for (uint256 i = 0; i < _wantsLength; i++) {
                uint256 _actualAmount = _amountsLocal[i];
                if (_actualAmount > 0) {
                    address _want = _wants[i];
                    if (!_isWantRatioIgnorable) {
                        if (_ratios[i] > 0) {
                            _actualAmount = (_ratios[i] * _minAmount) / _minAspect;
                            _amountsLocal[i] = _actualAmount;
                        } else {
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
            _deltaAssets = _report(_strategyAddress, _lendValue, 1);
            if (_minDeltaAssets > 0) {
                require(
                    _deltaAssets >= _minDeltaAssets ||
                        (_minDeltaAssets - _deltaAssets) * TEN_MILLION_BPS <=
                        _minDeltaAssets * deltaThreshold,
                    "not enough"
                );
            }
        }
        emit LendToStrategy(_strategyAddress, _wants, _amountsLocal, _lendValue);
    }

    /// @dev Report the current asset of strategy caller
    /// @param _strategies The address list of strategies to report
    /// Requirement: only keeper call
    /// Emits a {StrategyReported} event.
    function reportByKeeper(address[] memory _strategies) external isKeeperOrVaultOrGovOrDelegate {
        uint256 _strategiesLength = _strategies.length;
        for (uint256 i = 0; i < _strategiesLength; i++) {
            _report(_strategies[i], 0, 2);
        }
    }

    /// @dev Report the current asset of strategy caller
    /// Requirement: only the strategy caller is active
    /// Emits a {StrategyReported} event.
    function reportWithoutClaim() external isActiveStrategy(msg.sender) {
        _report(msg.sender, 0, 2);
    }

    /// @dev Report the current asset of strategy caller
    /// Requirement: only the strategy caller is active
    /// Emits a {StrategyReported} event.
    function report() external isActiveStrategy(msg.sender) {
        _report(msg.sender, 0, 0);
    }

    /// @notice Report the current asset of strategy
    /// @param _strategy The strategy address
    /// @param _lendValue The value to lend or redeem
    /// @param _type 0-harvest(claim); 1-lend; 2-report(without claim); 3-redeem;
    /// @return _deltaAsset The delta value between `_lastStrategyTotalDebt` and `_nowStrategyTotalDebt`
    function _report(
        address _strategy,
        uint256 _lendValue,
        uint256 _type
    ) private returns (uint256 _deltaAsset) {
        StrategyParams memory _strategyParam = strategies[_strategy];

        uint256 _lastStrategyTotalDebt = _strategyParam.totalDebt + _lendValue;
        uint256 _nowStrategyTotalDebt = IStrategy(_strategy).estimatedTotalAssets();
        if (_strategyParam.totalDebt < _nowStrategyTotalDebt) {
            _deltaAsset = _nowStrategyTotalDebt - _strategyParam.totalDebt;
        }
        // slither-disable-next-line uninitialized-local
        uint256 _gain;
        // slither-disable-next-line uninitialized-local
        uint256 _loss;

        if (_nowStrategyTotalDebt > _lastStrategyTotalDebt) {
            _gain = _nowStrategyTotalDebt - _lastStrategyTotalDebt;
        } else if (_nowStrategyTotalDebt < _lastStrategyTotalDebt) {
            _loss = _lastStrategyTotalDebt - _nowStrategyTotalDebt;
        }

        if (_strategyParam.enforceChangeLimit) {
            // slither-disable-next-line timestamp
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
        // slither-disable-next-line costly-loop
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
            _type
        );
    }
}
