// SPDX-License-Identifier: MIT

/*
    This file is part of the Enzyme Protocol.
    (c) Enzyme Council <council@enzyme.finance>
    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import './IDerivativePriceFeed.sol';

/// @title IDerivativePriceFeed Interface
/// @author Enzyme Council <security@enzyme.finance>
interface IAggregatedDerivativePriceFeed is IDerivativePriceFeed {
    function getPriceFeedForDerivative(address) external view returns (address);
}
