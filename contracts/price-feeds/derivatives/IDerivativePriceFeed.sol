// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

/// @title IDerivativePriceFeed Interface
/// @notice Simple interface for derivative price feed oracle implementations
interface IDerivativePriceFeed {
    function calcUnderlyingValues(address, uint256)
        external
        view
        returns (address[] memory, uint256[] memory);

    function isSupportedAsset(address) external view returns (bool);
}
