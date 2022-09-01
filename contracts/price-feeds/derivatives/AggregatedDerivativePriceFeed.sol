// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IAggregatedDerivativePriceFeed.sol";
import "./../../access-control/AccessControlMixin.sol";

/// @title AggregatedDerivativePriceFeed Contract
/// @notice Aggregates multiple derivative price feeds (e.g., Compound, Chai) and dispatches
/// rate requests to the appropriate feed
contract AggregatedDerivativePriceFeed is IAggregatedDerivativePriceFeed, AccessControlMixin {
    event DerivativeAdded(address indexed _derivative, address _priceFeed);

    event DerivativeRemoved(address indexed _derivative);

    event DerivativeUpdated(address indexed _derivative, address _prevPriceFeed, address _nextPriceFeed);

    mapping(address => address) private derivativeToPriceFeed;

    constructor(
        address[] memory _derivatives,
        address[] memory _priceFeeds,
        address _accessControlProxy
    ) {
        _initAccessControl(_accessControlProxy);

        if (_derivatives.length > 0) {
            __addDerivatives(_derivatives, _priceFeeds);
        }
    }

    /// @notice Gets the rates for 1 unit of the derivative to its underlying assets
    /// @param _derivative The derivative for which to get the rates
    /// @return _underlyings The underlying assets for the _derivative
    /// @return _underlyingAmounts The rates for the _derivative to the underlyings_
    function calcUnderlyingValues(address _derivative, uint256 _derivativeAmount)
        external
        view
        override
        returns (address[] memory _underlyings, uint256[] memory _underlyingAmounts)
    {
        address _derivativePriceFeed = derivativeToPriceFeed[_derivative];
        require(_derivativePriceFeed != address(0), "calcUnderlyingValues: _derivative is not supported");

        return
            IDerivativePriceFeed(_derivativePriceFeed).calcUnderlyingValues(
                _derivative,
                _derivativeAmount
            );
    }

    /// @dev This should be as low-cost and simple as possible
    /// @notice Checks whether an asset is a supported derivative
    /// @param _asset The asset to check
    /// @return isSupported_ True if the asset is a supported derivative
    function isSupportedAsset(address _asset) external view override returns (bool) {
        return derivativeToPriceFeed[_asset] != address(0);
    }

    //////////////////////////
    // DERIVATIVES REGISTRY //
    //////////////////////////

    /// @notice Adds a list of derivatives with the given price feed values
    /// @param _derivatives The derivatives to add
    /// @param _priceFeeds The ordered price feeds corresponding to the list of _derivatives
    /// Requirements: only governance or delegate role can call
    /// emit {DerivativeAdded} event
    function addDerivatives(address[] calldata _derivatives, address[] calldata _priceFeeds)
        external
        onlyGovOrDelegate
    {
        require(_derivatives.length > 0, "addDerivatives: _derivatives cannot be empty");

        __addDerivatives(_derivatives, _priceFeeds);
    }

    /// @notice Removes a list of derivatives
    /// @param _derivatives The derivatives to remove
    /// Requirements: only governance or delegate role can call
    /// emit {DerivativeRemoved} event
    function removeDerivatives(address[] calldata _derivatives) external onlyGovOrDelegate {
        require(_derivatives.length > 0, "removeDerivatives: _derivatives cannot be empty");

        for (uint256 i = 0; i < _derivatives.length; i++) {
            require(
                derivativeToPriceFeed[_derivatives[i]] != address(0),
                "removeDerivatives: Derivative not yet added"
            );

            delete derivativeToPriceFeed[_derivatives[i]];

            emit DerivativeRemoved(_derivatives[i]);
        }
    }

    /// @notice Updates a list of derivatives with the given price feed values
    /// @param _derivatives The derivatives to update
    /// @param _priceFeeds The ordered price feeds corresponding to the list of _derivatives
    /// Requirements: only governance or delegate role can call
    /// emit {DerivativeUpdated} event
    function updateDerivatives(address[] calldata _derivatives, address[] calldata _priceFeeds)
        external
        onlyGovOrDelegate
    {
        require(_derivatives.length > 0, "updateDerivatives: _derivatives cannot be empty");
        require(
            _derivatives.length == _priceFeeds.length,
            "updateDerivatives: Unequal _derivatives and _priceFeeds array lengths"
        );

        for (uint256 i = 0; i < _derivatives.length; i++) {
            address _prevPriceFeed = derivativeToPriceFeed[_derivatives[i]];

            require(_prevPriceFeed != address(0), "updateDerivatives: Derivative not yet added");
            require(_priceFeeds[i] != _prevPriceFeed, "updateDerivatives: Value already set");

            __validateDerivativePriceFeed(_derivatives[i], _priceFeeds[i]);

            derivativeToPriceFeed[_derivatives[i]] = _priceFeeds[i];

            emit DerivativeUpdated(_derivatives[i], _prevPriceFeed, _priceFeeds[i]);
        }
    }

    /// @dev Helper to add derivative-feed pairs
    function __addDerivatives(address[] memory _derivatives, address[] memory _priceFeeds) private {
        require(
            _derivatives.length == _priceFeeds.length,
            "__addDerivatives: Unequal _derivatives and _priceFeeds array lengths"
        );

        for (uint256 i = 0; i < _derivatives.length; i++) {
            require(
                derivativeToPriceFeed[_derivatives[i]] == address(0),
                "__addDerivatives: Already added"
            );

            __validateDerivativePriceFeed(_derivatives[i], _priceFeeds[i]);

            derivativeToPriceFeed[_derivatives[i]] = _priceFeeds[i];

            emit DerivativeAdded(_derivatives[i], _priceFeeds[i]);
        }
    }

    /// @dev Helper to validate a derivative price feed
    function __validateDerivativePriceFeed(address _derivative, address _priceFeed) private view {
        require(_derivative != address(0), "__validateDerivativePriceFeed: Empty _derivative");
        require(_priceFeed != address(0), "__validateDerivativePriceFeed: Empty _priceFeed");
        require(
            IDerivativePriceFeed(_priceFeed).isSupportedAsset(_derivative),
            "__validateDerivativePriceFeed: Unsupported derivative"
        );
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the registered price feed for a given derivative
    /// @return priceFeed_ The price feed contract address
    function getPriceFeedForDerivative(address _derivative) external view override returns (address) {
        return derivativeToPriceFeed[_derivative];
    }
}
