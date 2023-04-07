// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

interface ICustomPriceFeedAggregator {

    /// @notice Calculates the value of a base asset in terms of a quote asset (using a canonical rate)
    /// @param _baseAsset The base asset
    /// @param _baseAssetAmount The base asset amount to convert
    /// @return _quoteAssetAmount The equivalent quote asset amount (usd 1e8)
    /// @return _isValid True if the rates used in calculations are deemed valid
    function calcValueInUsd(
        address _baseAsset,
        uint256 _baseAssetAmount
    ) external view returns (uint256 _quoteAssetAmount, bool _isValid);

    /// @notice Calculates the value of a base asset in terms of a quote asset (using a canonical rate)
    /// @param _baseAsset The base asset
    /// @param _baseAssetAmount The base asset amount to convert
    /// @return _quoteAssetAmount The equivalent quote asset amount (eth 1e8)
    /// @return _isValid True if the rates used in calculations are deemed valid
    function calcValueInEth(
        address _baseAsset,
        uint256 _baseAssetAmount
    ) external view returns (uint256 _quoteAssetAmount, bool _isValid);

    /// @notice Gets the unit variable value for a primitive
    /// @param _asset the base asset
    /// @return _unit The unit variable value
    function getAssetUnit(address _asset) external view returns (uint256 _unit);

    /// @notice Checks whether an asset is a supported primitive of the price feed
    /// @param _asset The asset to check
    /// @return _isSupported True if the asset is a supported primitive
    function isSupportedAsset(address _asset) external view returns (bool _isSupported);
}