// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BaseStrategy.sol";

abstract contract BaseClaimableStrategy is BaseStrategy {
    /// @notice Provide a signal to the keeper that `harvest()` should be called.
    /// @dev if strategy does not need claim return address(0).
    /// @param _rewardsTokens reward token.
    /// @param _pendingAmounts pending reward amount.
    function getPendingRewards()
        public
        view
        virtual
        returns (
            address[] memory _rewardsTokens,
            uint256[] memory _pendingAmounts
        );

    /// @notice Collect the rewards from 3rd protocol
    function claimRewards()
        internal
        virtual
        returns (
            address[] memory _rewardsTokens,
            uint256[] memory _claimAmounts
        );

    /// @notice Harvests the Strategy, recognizing any profits or losses and adjusting the Strategy's position.
    function harvest()
        external
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
        report(_rewardsTokens, _claimAmounts);
    }
}
