// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "./IStrategy.sol";

/// @title IStrategy interface
interface IClaimableStrategy {
    // /// @notice Harvests the Strategy,
    // ///     recognizing any profits or losses and adjusting the Strategy's position.
    // /// @return _rewardsTokens The list of the reward token
    // /// @return _claimAmounts The list of the reward amount claimed
    // function harvest() external returns (address[] memory _rewardsTokens, uint256[] memory _claimAmounts);

    /// @notice Transfer rewardToken to Harvester
    /// @return _rewardTokens The address list of the reward token
    /// @return _rewardAmounts The amount list of the reward token
    /// @return _sellTo The address of target token,sell to wants radios when _sellTo is null
    /// @return _needReInvest The sellTo Token is need reInvest to the strategy
    function collectReward()
        external
        returns (
            address[] memory _rewardTokens,
            uint256[] memory _rewardAmounts,
            address _sellTo,
            bool _needReInvest
        );

    function exchangeFinishCallback(uint256 _amount) external;
}
