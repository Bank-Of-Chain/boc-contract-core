// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./derivatives/IAggregatedDerivativePriceFeed.sol";
import "./derivatives/IDerivativePriceFeed.sol";
import "./primitives/IPrimitivePriceFeed.sol";
import "./../access-control/AccessControlMixin.sol";
import "./IValueInterpreter.sol";

import "hardhat/console.sol";

/// @title ValueInterpreter Contract
/// @author Enzyme Council <security@enzyme.finance>
/// @notice Interprets price feeds to provide covert value between asset pairs
/// @dev This contract contains several 'live' value calculations, which for this release are simply
/// aliases to their 'canonical' value counterparts since the only primitive price feed (Chainlink)
/// is immutable in this contract and only has one type of value. Including the 'live' versions of
/// functions only serves as a placeholder for infrastructural components and plugins (e.g., policies)
/// to explicitly define the types of values that they should (and will) be using in a future release.
contract ValueInterpreter is IValueInterpreter, AccessControlMixin {
    event UpdatePrimitivePriceFeed(address primitivePriceFeed);
    event UpdateAggregatedDerivativePriceFeed(
        address aggregatedDerivativePriceFeed
    );

    address private AGGREGATED_DERIVATIVE_PRICE_FEED;
    address private PRIMITIVE_PRICE_FEED;

    constructor(
        address _primitivePriceFeed,
        address _aggregatedDerivativePriceFeed,
        address _accessControlProxy
    ) {
        AGGREGATED_DERIVATIVE_PRICE_FEED = _aggregatedDerivativePriceFeed;
        PRIMITIVE_PRICE_FEED = _primitivePriceFeed;
        _initAccessControl(_accessControlProxy);
    }

    // EXTERNAL FUNCTIONS

    /// @notice Calculates the total value of given amounts of assets in a single quote asset
    /// @param _baseAssets The assets to convert
    /// @param _amounts The amounts of the _baseAssets to convert
    /// @param _quoteAsset The asset to which to convert
    /// @return value_ The sum value of _baseAssets, denominated in the _quoteAsset
    /// @dev Does not alter protocol state,
    /// but not a view because calls to price feeds can potentially update third party state.
    /// Does not handle a derivative quote asset.
    function calcCanonicalAssetsTotalValue(
        address[] memory _baseAssets,
        uint256[] memory _amounts,
        address _quoteAsset
    ) external view override returns (uint256 value_) {
        require(
            _baseAssets.length == _amounts.length,
            "calcCanonicalAssetsTotalValue: Arrays unequal lengths"
        );
        require(
            IPrimitivePriceFeed(PRIMITIVE_PRICE_FEED).isSupportedAsset(
                _quoteAsset
            ),
            string(
                abi.encodePacked(
                    "calcCanonicalAssetsTotalValue: Unsupported _quoteAsset ",
                    Strings.toHexString(uint160(_quoteAsset), 20)
                )
            )
        );

        bool isValid_ = true;
        for (uint256 i = 0; i < _baseAssets.length; i++) {
            (uint256 assetValue, bool assetValueIsValid) = __calcAssetValue(
                _baseAssets[i],
                _amounts[i],
                _quoteAsset
            );
            value_ = value_ + assetValue;
            if (!assetValueIsValid) {
                isValid_ = false;
            }
        }
        require(isValid_, "Invalid rate");
        return value_;
    }

    /// @notice Calculates the value of a given amount of one asset in terms of another asset
    /// @param _baseAsset The asset from which to convert
    /// @param _amount The amount of the _baseAsset to convert
    /// @param _quoteAsset The asset to which to convert
    /// @return value_ The equivalent quantity in the _quoteAsset
    /// @dev Does not alter protocol state,
    /// but not a view because calls to price feeds can potentially update third party state
    function calcCanonicalAssetValue(
        address _baseAsset,
        uint256 _amount,
        address _quoteAsset
    ) external view override returns (uint256 value_) {
        if (_baseAsset == _quoteAsset || _amount == 0) {
            return _amount;
        }

        //        require(
        //            IPrimitivePriceFeed(PRIMITIVE_PRICE_FEED).isSupportedAsset(_quoteAsset),
        //            'calcCanonicalAssetValue: Unsupported _quoteAsset'
        //        );
        bool isValid_;
        (value_, isValid_) = __calcAssetValue(_baseAsset, _amount, _quoteAsset);
        require(isValid_, "Invalid rate");
        return value_;
    }

    /*
     * 资产的usd价值
     * _baseAsset: 源token地址
     * _amount: 源token数量
     * @return usd(1e18)
     */
    function calcCanonicalAssetValueInUsd(address _baseAsset, uint256 _amount)
        external
        view
        override
        returns (uint256 value_)
    {
        if (_amount == 0) {
            return _amount;
        }
        bool isValid_;
        (value_, isValid_) = __calcAssetValueInUsd(_baseAsset, _amount);
        require(isValid_, "Invalid rate");
        return value_;
    }

    /*
     * baseUnit数量资产的usd价值
     * _baseAsset: 源token地址
     * @return usd(1e18)
     */
    function price(address _baseAsset)
        external
        view
        override
        returns (uint256 value_)
    {
        // Handle case that asset is a primitive
        if (
            IPrimitivePriceFeed(PRIMITIVE_PRICE_FEED).isSupportedAsset(
                _baseAsset
            )
        ) {
            bool isValid_;
            (value_, isValid_) = IPrimitivePriceFeed(PRIMITIVE_PRICE_FEED)
                .calcValueInUsd(
                    _baseAsset,
                    IPrimitivePriceFeed(PRIMITIVE_PRICE_FEED).getAssetUnit(
                        _baseAsset
                    )
                );
            require(isValid_, "Invalid rate");
            return value_;
        }
        revert(
            string(
                abi.encodePacked(
                    "__calcAssetValue: Unsupported _baseAsset ",
                    Strings.toHexString(uint160(_baseAsset), 20)
                )
            )
        );
    }

    // PRIVATE FUNCTIONS
    /// @dev Helper to differentially calculate an asset value
    /// based on if it is a primitive or derivative asset.
    function __calcAssetValueInUsd(address _baseAsset, uint256 _amount)
        private
        view
        returns (uint256 value_, bool isValid_)
    {
        if (_amount == 0) {
            return (_amount, true);
        }

        // Handle case that asset is a primitive
        if (
            IPrimitivePriceFeed(PRIMITIVE_PRICE_FEED).isSupportedAsset(
                _baseAsset
            )
        ) {
            return
                IPrimitivePriceFeed(PRIMITIVE_PRICE_FEED).calcValueInUsd(
                    _baseAsset,
                    _amount
                );
        }

        // Handle case that asset is a derivative
        address derivativePriceFeed = IAggregatedDerivativePriceFeed(
            AGGREGATED_DERIVATIVE_PRICE_FEED
        ).getPriceFeedForDerivative(_baseAsset);
        if (derivativePriceFeed != address(0)) {
            return
                __calcDerivativeValueInUsd(
                    derivativePriceFeed,
                    _baseAsset,
                    _amount
                );
        }

        revert(
            string(
                abi.encodePacked(
                    "__calcAssetValue: Unsupported _baseAsset ",
                    Strings.toHexString(uint160(_baseAsset), 20)
                )
            )
        );
    }

    /// @dev Helper to differentially calculate an asset value
    /// based on if it is a primitive or derivative asset.
    function __calcAssetValue(
        address _baseAsset,
        uint256 _amount,
        address _quoteAsset
    ) private view returns (uint256 value_, bool isValid_) {
        if (_baseAsset == _quoteAsset || _amount == 0) {
            return (_amount, true);
        }

        // Handle case that asset is a primitive
        if (
            IPrimitivePriceFeed(PRIMITIVE_PRICE_FEED).isSupportedAsset(
                _baseAsset
            ) &&
            IPrimitivePriceFeed(PRIMITIVE_PRICE_FEED).isSupportedAsset(
                _quoteAsset
            )
        ) {
            return
                IPrimitivePriceFeed(PRIMITIVE_PRICE_FEED).calcCanonicalValue(
                    _baseAsset,
                    _amount,
                    _quoteAsset
                );
        }

        // Handle case that asset is a derivative
        address derivativePriceFeed = IAggregatedDerivativePriceFeed(
            AGGREGATED_DERIVATIVE_PRICE_FEED
        ).getPriceFeedForDerivative(_baseAsset);
        if (derivativePriceFeed != address(0)) {
            return
                __calcDerivativeValue(
                    derivativePriceFeed,
                    _baseAsset,
                    _amount,
                    _quoteAsset
                );
        }

        revert(
            string(
                abi.encodePacked(
                    "__calcAssetValue: Unsupported _baseAsset ",
                    Strings.toHexString(uint160(_baseAsset), 20)
                )
            )
        );
    }

    /// @dev Helper to calculate the value of a derivative in an arbitrary asset.
    /// Handles multiple underlying assets (e.g., Uniswap and Balancer pool tokens).
    /// Handles underlying assets that are also derivatives (e.g., a cDAI-ETH LP)
    function __calcDerivativeValueInUsd(
        address _derivativePriceFeed,
        address _derivative,
        uint256 _amount
    ) private view returns (uint256 value_, bool isValid_) {
        (
            address[] memory underlyings,
            uint256[] memory underlyingAmounts
        ) = IDerivativePriceFeed(_derivativePriceFeed).calcUnderlyingValues(
                _derivative,
                _amount
            );

        require(
            underlyings.length > 0,
            "__calcDerivativeValue: No underlyings"
        );
        require(
            underlyings.length == underlyingAmounts.length,
            "__calcDerivativeValue: Arrays unequal lengths"
        );

        // Let validity be negated if any of the underlying value calculations are invalid
        isValid_ = true;
        for (uint256 i = 0; i < underlyings.length; i++) {
            (
                uint256 underlyingValue,
                bool underlyingValueIsValid
            ) = __calcAssetValueInUsd(underlyings[i], underlyingAmounts[i]);

            if (!underlyingValueIsValid) {
                isValid_ = false;
            }
            value_ = value_ + underlyingValue;
        }
    }

    /// @dev Helper to calculate the value of a derivative in an arbitrary asset.
    /// Handles multiple underlying assets (e.g., Uniswap and Balancer pool tokens).
    /// Handles underlying assets that are also derivatives (e.g., a cDAI-ETH LP)
    function __calcDerivativeValue(
        address _derivativePriceFeed,
        address _derivative,
        uint256 _amount,
        address _quoteAsset
    ) private view returns (uint256 value_, bool isValid_) {
        (
            address[] memory underlyings,
            uint256[] memory underlyingAmounts
        ) = IDerivativePriceFeed(_derivativePriceFeed).calcUnderlyingValues(
                _derivative,
                _amount
            );

        require(
            underlyings.length > 0,
            "__calcDerivativeValue: No underlyings"
        );
        require(
            underlyings.length == underlyingAmounts.length,
            "__calcDerivativeValue: Arrays unequal lengths"
        );

        // Let validity be negated if any of the underlying value calculations are invalid
        isValid_ = true;
        for (uint256 i = 0; i < underlyings.length; i++) {
            (
                uint256 underlyingValue,
                bool underlyingValueIsValid
            ) = __calcAssetValue(
                    underlyings[i],
                    underlyingAmounts[i],
                    _quoteAsset
                );

            if (!underlyingValueIsValid) {
                isValid_ = false;
            }
            value_ = value_ + underlyingValue;
        }
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the `AGGREGATED_DERIVATIVE_PRICE_FEED` variable
    /// @return aggregatedDerivativePriceFeed_ The `AGGREGATED_DERIVATIVE_PRICE_FEED` variable value
    function getAggregatedDerivativePriceFeed()
        external
        view
        returns (address aggregatedDerivativePriceFeed_)
    {
        return AGGREGATED_DERIVATIVE_PRICE_FEED;
    }

    /// @notice Gets the `PRIMITIVE_PRICE_FEED` variable
    /// @return primitivePriceFeed_ The `PRIMITIVE_PRICE_FEED` variable value
    function getPrimitivePriceFeed()
        external
        view
        returns (address primitivePriceFeed_)
    {
        return PRIMITIVE_PRICE_FEED;
    }

    ///////////////////
    // STATE SETTERS //
    ///////////////////
    function setPrimitivePriceFeed(address _primitivePriceFeed)
        external
        onlyGovOrDelegate
    {
        PRIMITIVE_PRICE_FEED = _primitivePriceFeed;
        emit UpdatePrimitivePriceFeed(_primitivePriceFeed);
    }

    function setAggregatedDerivativePriceFeed(
        address _aggregatedDerivativePriceFeed
    ) external onlyGovOrDelegate {
        AGGREGATED_DERIVATIVE_PRICE_FEED = _aggregatedDerivativePriceFeed;
        emit UpdateAggregatedDerivativePriceFeed(
            _aggregatedDerivativePriceFeed
        );
    }
}
