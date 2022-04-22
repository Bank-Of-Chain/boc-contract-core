// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
/**
 * @title USDI Vault Admin Contract
 * @notice The VaultAdmin contract makes configuration and admin calls on the vault.
 * @author Bank OF CHAIN Protocol Inc
 */

import "./VaultStorage.sol";
import "../library/BocRoles.sol";

import "../strategy/IStrategy.sol";
import "../price-feeds/IValueInterpreter.sol";
import "../util/Helpers.sol";

contract VaultAdmin is VaultStorage {
    using EnumerableSet for EnumerableSet.AddressSet;
    using IterableIntMap for IterableIntMap.AddressToIntMap;

    /// @notice Shutdown the vault when an emergency occurs, cannot mint/burn.
    function setEmergencyShutdown(bool active) external isVaultManager {
        emergencyShutdown = active;
        emit SetEmergencyShutdown(active);
    }

    /// @notice set adjustPositionPeriod true when adjust position occurs, cannot remove add asset/strategy and cannot mint/burn.
    function setAdjustPositionPeriod(bool _adjustPositionPeriod)
        external
        isKeeper
    {
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
    function setTreasuryAddress(address _address)
        external
        onlyRole(BocRoles.GOV_ROLE)
    {
        treasury = _address;
        emit TreasuryAddressChanged(_address);
    }

    function setUSDiAddress(address _address)
        external
        onlyRole(BocRoles.GOV_ROLE)
    {
        require(address(usdi) == address(0), "USDi has been set");
        require(_address != address(0), "USDi ad is 0");
        usdi = USDi(_address);
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

    function setStrategyEnforceChangeLimit(address _strategy, bool _enabled)
        external
        isVaultManager
    {
        strategies[_strategy].enforceChangeLimit = _enabled;
    }

    function setStrategySetLimitRatio(
        address _strategy,
        uint256 _lossRatioLimit,
        uint256 _profitLimitRatio
    ) external isVaultManager {
        strategies[_strategy].lossLimitRatio = _lossRatioLimit;
        strategies[_strategy].profitLimitRatio = _profitLimitRatio;
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

    /// @notice Added support for specific asset.
    function addAsset(address _asset) external isVaultManager {
        require(!assetSet.contains(_asset), "existed");
        assetSet.add(_asset);
        // Verify that our oracle supports the asset
        // slither-disable-next-line unused-return
        IValueInterpreter(valueInterpreter).price(_asset);
        trackedAssetsMap.plus(_asset, 1);
        trackedAssetDecimalsMap[_asset] = Helpers.getDecimals(_asset);
        emit AddAsset(_asset);
    }

    /// @notice Remove support for specific asset.
    function removeAsset(address _asset) external isVaultManager {
        require(assetSet.contains(_asset), "not exist");
        assetSet.remove(_asset);
        trackedAssetsMap.minus(_asset, 1);
        if (
            trackedAssetsMap.get(_asset) <= 0 &&
            IERC20Upgradeable(_asset).balanceOf(address(this)) == 0
        ) {
            trackedAssetsMap.remove(_asset);
            delete trackedAssetDecimalsMap[_asset];
        }
        emit RemoveAsset(_asset);
    }

    /// @notice Add strategy to strategy list
    /// @dev The strategy added to the strategy list,
    ///      Vault may invest funds into the strategy,
    ///      and the strategy will invest the funds in the 3rd protocol
    function addStrategy(StrategyAdd[] memory strategyAdds)
        external
        isVaultManager
    {
        address[] memory _strategies = new address[](strategyAdds.length);
        for (uint256 i = 0; i < strategyAdds.length; i++) {
            StrategyAdd memory strategyAdd = strategyAdds[i];
            address _strategy = strategyAdd.strategy;
            require(
                (_strategy != ZERO_ADDRESS) &&
                    (!strategySet.contains(_strategy)) &&
                    (IStrategy(_strategy).vault() == address(this)),
                "Strategy is invalid"
            );
            _strategies[i] = _strategy;
            _addStrategy(
                _strategy,
                strategyAdd.profitLimitRatio,
                strategyAdd.lossLimitRatio
            );
            address[] memory _wants = IStrategy(_strategy).getWants();
            for (uint256 j = 0; j < _wants.length; j++) {
                trackedAssetsMap.plus(_wants[j], 1);
                if (trackedAssetDecimalsMap[_wants[j]] == 0) {
                    trackedAssetDecimalsMap[_wants[j]] = Helpers.getDecimals(
                        _wants[j]
                    );
                }
            }
        }

        emit AddStrategies(_strategies);
    }

    /**
     * add strategy
     **/
    function _addStrategy(
        address strategy,
        uint256 _profitLimitRatio,
        uint256 _lossLimitRatio
    ) internal {
        //Add strategy to approved strategies
        strategies[strategy] = StrategyParams({
            lastReport: block.timestamp,
            totalDebt: 0,
            profitLimitRatio: _profitLimitRatio,
            lossLimitRatio: _lossLimitRatio,
            enforceChangeLimit: true
        });
        strategySet.add(strategy);
    }

    /// @notice Remove strategy from strategy list
    /// @dev The removed policy withdraws funds from the 3rd protocol and returns to the Vault
    function removeStrategy(address[] memory _strategies)
        external
        isVaultManager
    {
        for (uint256 i = 0; i < _strategies.length; i++) {
            require(strategySet.contains(_strategies[i]), "Strategy not exist");
            _removeStrategy(_strategies[i], false);
        }
        emit RemoveStrategies(_strategies);
    }

    function forceRemoveStrategy(address _strategy) external onlyGovOrDelegate {
        _removeStrategy(_strategy, true);
        emit RemoveStrategyByForce(_strategy);
    }

    /**
     * @dev Remove a strategy from the Vault.
     * @param _addr Address of the strategy to remove
     */
    function _removeStrategy(address _addr, bool _force) internal {
        // Withdraw all assets
        try IStrategy(_addr).repay(MAX_BPS, MAX_BPS) {} catch {
            if (!_force) {
                revert();
            }
        }

        address[] memory _wants = IStrategy(_addr).getWants();
        for (uint256 i = 0; i < _wants.length; i++) {
            address wantToken = _wants[i];
            trackedAssetsMap.minus(wantToken, 1);
            if (
                trackedAssetsMap.get(wantToken) <= 0 &&
                IERC20Upgradeable(wantToken).balanceOf(address(this)) == 0
            ) {
                trackedAssetsMap.remove(wantToken);
            }
        }
        totalDebt -= strategies[_addr].totalDebt;
        delete strategies[_addr];
        strategySet.remove(_addr);
        _removeStrategyFromQueue(_addr);
    }

    /***************************************
                     WithdrawalQueue
     ****************************************/
    function getWithdrawalQueue() external view returns (address[] memory) {
        return withdrawQueue;
    }

    //advance queue
    function setWithdrawalQueue(address[] memory queues) external isKeeper {
        for (uint256 i = 0; i < queues.length; i++) {
            address strategy = queues[i];
            require(strategySet.contains(strategy), "strategy not exist");
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

    function removeStrategyFromQueue(address[] memory _strategies)
        external
        isKeeper
    {
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
