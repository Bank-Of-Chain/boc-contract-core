// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

/// @title ICustomPriceFeed interface
interface ICustomPriceFeed {

    /// @notice Calculates the value of a base asset in terms of a quote asset (using a canonical rate)
    /// @param _amount The base asset amount to convert
    /// @return _usdInValue The equivalent quote asset amount (usd 1e8)
    function calcValueInUsd(
        uint256 _amount
    ) external view returns (uint256 _usdInValue);

    /// @notice Calculates the value of a base asset in terms of a quote asset (using a canonical rate)
    /// @param _amount The base asset amount to convert
    /// @return _usdInEth The equivalent quote asset amount (eth 1e8)
    function calcValueInEth(
        uint256 _amount
    ) external view returns (uint256 _usdInEth);

    /// @notice Gets the unit variable value for a primitive
    /// @return _unit The unit variable value
    function getAssetUnit() external view returns (uint256 _unit);
}
