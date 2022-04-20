// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IPrimitivePriceFeed {
    function calcCanonicalValue(
        address,
        uint256,
        address
    ) external view returns (uint256, bool);

    function calcValueInUsd(
        address _baseAsset,
        uint256 _baseAssetAmount
    ) external view returns (uint256 quoteAssetAmount_, bool isValid_);

    function getAssetUnit(address) external view returns (uint256);

    function isSupportedAsset(address) external view returns (bool);
}
