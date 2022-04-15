// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import './IDerivativePriceFeed.sol';

/// @title IDerivativePriceFeed Interface
interface IAggregatedDerivativePriceFeed is IDerivativePriceFeed {
    function getPriceFeedForDerivative(address) external view returns (address);
}
