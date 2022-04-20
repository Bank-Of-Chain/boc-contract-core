// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface Mock3rdPool is IERC20Upgradeable, IERC20MetadataUpgradeable {
    function underlyingToken() external view returns (address);

    function rewardsToken() external view returns (address);

    function deposit(address[] memory _assets, uint256[] memory _amounts)
        external;

    function withdraw(uint256 _shares)
        external
        returns (address[] memory _assets, uint256[] memory _amounts);

    function pricePerShare() external view returns (uint256);

    function getPendingRewards()
        external
        view
        returns (
            address[] memory _rewardsTokens,
            uint256[] memory _pendingAmounts
        );

    function claim() external returns (uint256[] memory _claimAmounts);
}
