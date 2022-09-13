// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

/// @title IBasicToken Interface
interface IBasicToken {
    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}
