// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "./BaseStrategy.sol";

/// @title BaseClaimableStrategy
/// @author Bank of Chain Protocol Inc
abstract contract BaseClaimableStrategy is BaseStrategy {

    /// @inheritdoc BaseStrategy
    function harvest()
        public
        virtual
        override
        returns (
            address[] memory _rewardsTokens,
            uint256[] memory _claimAmounts
        )
    {
        (_rewardsTokens, _claimAmounts) = claimRewards();
        // transfer reward token to harvester
        transferTokensToTarget(harvester, _rewardsTokens, _claimAmounts);
        vault.report(_rewardsTokens, _claimAmounts);
    }

    /// @notice Collect the rewards from 3rd protocol
    /// @return _rewardsTokens The list of the reward token
    /// @return _claimAmounts The list of the reward amount claimed
    function claimRewards()
        internal
        virtual
        returns (
            address[] memory _rewardsTokens,
            uint256[] memory _claimAmounts
        );

    /// @inheritdoc BaseStrategy
    function repay(uint256 _repayShares, uint256 _totalShares,uint256 _outputCode)
        public
        virtual
        override
        onlyVault
        returns (address[] memory _assets, uint256[] memory _amounts)
    {
        // if withdraw all need claim rewards
        if (_repayShares == _totalShares) {
            harvest();
        }
        return super.repay(_repayShares, _totalShares,_outputCode);
    }
}
