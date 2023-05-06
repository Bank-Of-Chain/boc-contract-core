// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "./ICustomPriceFeedAggregator.sol";
import "./ICustomPriceFeed.sol";
import "./../../access-control/AccessControlMixin.sol";

contract CustomPriceFeedAggregator is ICustomPriceFeedAggregator, AccessControlMixin {
    mapping(address => ICustomPriceFeed) customPriceFeeds;

    constructor(address[] memory _baseAssets, address[] memory _priceFeeds, address _accessControlProxy) {
        require(_baseAssets.length == _priceFeeds.length, "");

        for (uint256 i = 0; i < _baseAssets.length; ++i) {
            customPriceFeeds[_baseAssets[i]] = ICustomPriceFeed(_priceFeeds[i]);
        }

        _initAccessControl(_accessControlProxy);
    }

    function addOrReplaceCustomPriceFeed(
        address _baseAsset,
        address _customPriceFeed
    ) external onlyGovOrDelegate {
        customPriceFeeds[_baseAsset] = ICustomPriceFeed(_customPriceFeed);
    }

    function removeCustomPriceFeed(address _baseAsset) external onlyGovOrDelegate {
        delete customPriceFeeds[_baseAsset];
    }

    function calcValueInUsd(
        address _baseAsset,
        uint256 _baseAssetAmount
    ) external view override returns (uint256 _quoteAssetAmount, bool _isValid) {
        if (address(customPriceFeeds[_baseAsset]) == address(0)) {
            return (0, false);
        }

        return (customPriceFeeds[_baseAsset].calcValueInUsd(_baseAssetAmount), true);
    }

    function calcValueInEth(
        address _baseAsset,
        uint256 _baseAssetAmount
    ) external view override returns (uint256 _quoteAssetAmount, bool _isValid) {
        if (address(customPriceFeeds[_baseAsset]) == address(0)) {
            return (0, false);
        }

        return (customPriceFeeds[_baseAsset].calcValueInEth(_baseAssetAmount), true);
    }

    function getAssetUnit(address _asset) external view override returns (uint256 _unit) {
        return customPriceFeeds[_asset].getAssetUnit();
    }

    function getRateAsset(
        address _asset
    ) external view override returns (IPrimitivePriceFeed.RateAsset _rateAsset) {
        return customPriceFeeds[_asset].getRateAsset();
    }

    function isSupportedAsset(address _asset) external view override returns (bool _isSupported) {
        return address(customPriceFeeds[_asset]) != address(0);
    }
}
