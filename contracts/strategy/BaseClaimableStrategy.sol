// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./BaseStrategy.sol";

abstract contract BaseClaimableStrategy is BaseStrategy {
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
        vault.report(_rewardsTokens, _claimAmounts);
    }

    /// @notice Strategy repay the funds to vault
    /// @param _repayShares Numerator
    /// @param _totalShares Denominator
    function repay(uint256 _repayShares, uint256 _totalShares,uint256 _outputCode)
        public
        virtual
        override
        onlyVault
        returns (address[] memory _assets, uint256[] memory _amounts)
    {
        // if withdraw all need claim rewards
        if (_repayShares == _totalShares) {
            (
                address[] memory _rewardsTokens,
                uint256[] memory _claimAmounts
            ) = claimRewards();
            // transfer reward token to harvester
            transferTokensToTarget(harvester, _rewardsTokens, _claimAmounts);
        }
        return super.repay(_repayShares, _totalShares,_outputCode);
    }
}
