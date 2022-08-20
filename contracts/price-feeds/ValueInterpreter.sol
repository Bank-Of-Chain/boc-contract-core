// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./derivatives/IAggregatedDerivativePriceFeed.sol";
import "./derivatives/IDerivativePriceFeed.sol";
import "./primitives/IPrimitivePriceFeed.sol";
import "./../access-control/AccessControlMixin.sol";
import "./IValueInterpreter.sol";

/// @title ValueInterpreter Contract
/// @notice Interprets price feeds to provide covert value between asset pairs
/// @dev This contract contains several 'live' value calculations, which for this release are simply
/// aliases to their 'canonical' value counterparts since the only primitive price feed (Chainlink)
/// is immutable in this contract and only has one type of value. Including the 'live' versions of
/// functions only serves as a placeholder for infrastructural components and plugins (e.g., policies)
/// to explicitly define the types of values that they should (and will) be using in a future release.
contract ValueInterpreter is IValueInterpreter, AccessControlMixin {
    event UpdatePrimitivePriceFeed(address _primitivePriceFeed);
    event UpdateAggregatedDerivativePriceFeed(
        address _aggregatedDerivativePriceFeed
    );

    address private aggregatedDerivativePriceFeed;
    address private primitivePriceFeed;

    constructor(
        address _primitivePriceFeed,
        address _aggregatedDerivativePriceFeed,
        address _accessControlProxy
    ) {
        aggregatedDerivativePriceFeed = _aggregatedDerivativePriceFeed;
        primitivePriceFeed = _primitivePriceFeed;
        _initAccessControl(_accessControlProxy);
    }

    // EXTERNAL FUNCTIONS

    /// @inheritdoc IValueInterpreter
    function calcCanonicalAssetsTotalValue(
        address[] calldata _baseAssets,
        uint256[] calldata _amounts,
        address _quoteAsset
    ) external view override returns (uint256 _value) {
        require(
            _baseAssets.length == _amounts.length,
            "calcCanonicalAssetsTotalValue: Arrays unequal lengths"
        );
        require(
            IPrimitivePriceFeed(primitivePriceFeed).isSupportedAsset(
                _quoteAsset
            ),
            string(
                abi.encodePacked(
                    "calcCanonicalAssetsTotalValue: Unsupported _quoteAsset ",
                    Strings.toHexString(uint160(_quoteAsset), 20)
                )
            )
        );

        bool _isValid = true;
        for (uint256 i = 0; i < _baseAssets.length; i++) {
            (uint256 _assetValue, bool _assetValueIsValid) = __calcAssetValue(
                _baseAssets[i],
                _amounts[i],
                _quoteAsset
            );
            _value = _value + _assetValue;
            if (!_assetValueIsValid) {
                _isValid = false;
            }
        }
        require(_isValid, "Invalid rate");
        return _value;
    }

    /// @inheritdoc IValueInterpreter
    function calcCanonicalAssetValue(
        address _baseAsset,
        uint256 _amount,
        address _quoteAsset
    ) external view override returns (uint256 _value) {
        if (_baseAsset == _quoteAsset || _amount == 0) {
            return _amount;
        }
        bool _isValid;
        (_value, _isValid) = __calcAssetValue(_baseAsset, _amount, _quoteAsset);
        require(_isValid, "Invalid rate");
        return _value;
    }

    /// @inheritdoc IValueInterpreter
    function calcCanonicalAssetValueInUsd(address _baseAsset, uint256 _amount)
        external
        view
        override
        returns (uint256 _value)
    {
        if (_amount == 0) {
            return _amount;
        }
        bool _isValid;
        (_value, _isValid) = __calcAssetValueInUsd(_baseAsset, _amount);
        require(_isValid, "Invalid rate");
        return _value;
    }

    /// @inheritdoc IValueInterpreter
    function price(address _baseAsset)
        external
        view
        override
        returns (uint256 _value)
    {
        // Handle case that asset is a primitive
        if (
            IPrimitivePriceFeed(primitivePriceFeed).isSupportedAsset(
                _baseAsset
            )
        ) {
            bool _isValid;
            (_value, _isValid) = IPrimitivePriceFeed(primitivePriceFeed)
                .calcValueInUsd(
                    _baseAsset,
                    IPrimitivePriceFeed(primitivePriceFeed).getAssetUnit(
                        _baseAsset
                    )
                );
            require(_isValid, "Invalid rate");
            return _value;
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

    ////// PRIVATE FUNCTIONS //////

    /// @dev Helper to differentially calculate an asset value
    /// based on if it is a primitive or derivative asset.
    function __calcAssetValueInUsd(address _baseAsset, uint256 _amount)
        private
        view
        returns (uint256 _value, bool _isValid)
    {
        if (_amount == 0) {
            return (_amount, true);
        }

        // Handle case that asset is a primitive
        if (
            IPrimitivePriceFeed(primitivePriceFeed).isSupportedAsset(
                _baseAsset
            )
        ) {
            return
                IPrimitivePriceFeed(primitivePriceFeed).calcValueInUsd(
                    _baseAsset,
                    _amount
                );
        }

        // Handle case that asset is a derivative
        address _derivativePriceFeed = IAggregatedDerivativePriceFeed(
            aggregatedDerivativePriceFeed
        ).getPriceFeedForDerivative(_baseAsset);
        if (_derivativePriceFeed != address(0)) {
            return
                __calcDerivativeValueInUsd(
                    _derivativePriceFeed,
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
    ) private view returns (uint256 _value, bool _isValid) {
        if (_baseAsset == _quoteAsset || _amount == 0) {
            return (_amount, true);
        }

        // Handle case that asset is a primitive
        if (
            IPrimitivePriceFeed(primitivePriceFeed).isSupportedAsset(
                _baseAsset
            ) &&
            IPrimitivePriceFeed(primitivePriceFeed).isSupportedAsset(
                _quoteAsset
            )
        ) {
            return
                IPrimitivePriceFeed(primitivePriceFeed).calcCanonicalValue(
                    _baseAsset,
                    _amount,
                    _quoteAsset
                );
        }

        // Handle case that asset is a derivative
        address _derivativePriceFeed = IAggregatedDerivativePriceFeed(
            aggregatedDerivativePriceFeed
        ).getPriceFeedForDerivative(_baseAsset);
        if (_derivativePriceFeed != address(0)) {
            return
                __calcDerivativeValue(
                    _derivativePriceFeed,
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
    ) private view returns (uint256 _value, bool _isValid) {
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
        _isValid = true;
        for (uint256 i = 0; i < underlyings.length; i++) {
            (
                uint256 underlyingValue,
                bool underlyingValueIsValid
            ) = __calcAssetValueInUsd(underlyings[i], underlyingAmounts[i]);

            if (!underlyingValueIsValid) {
                _isValid = false;
            }
            _value = _value + underlyingValue;
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
    ) private view returns (uint256 _value, bool _isValid) {
        (
            address[] memory _underlyings,
            uint256[] memory _underlyingAmounts
        ) = IDerivativePriceFeed(_derivativePriceFeed).calcUnderlyingValues(
                _derivative,
                _amount
            );

        require(
            _underlyings.length > 0,
            "__calcDerivativeValue: No underlyings"
        );
        require(
            _underlyings.length ==_underlyingAmounts.length,
            "__calcDerivativeValue: Arrays unequal lengths"
        );

        // Let validity be negated if any of the underlying value calculations are invalid
        _isValid = true;
        for (uint256 i = 0; i < _underlyings.length; i++) {
            (
                uint256 _underlyingValue,
                bool _underlyingValueIsValid
            ) = __calcAssetValue(
                    _underlyings[i],
                    _underlyingAmounts[i],
                    _quoteAsset
                );

            if (!_underlyingValueIsValid) {
                _isValid = false;
            }
            _value = _value + _underlyingValue;
        }
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the `aggregatedDerivativePriceFeed` variable
    /// @return _aggregatedDerivativePriceFeed The `aggregatedDerivativePriceFeed` variable value
    function getAggregatedDerivativePriceFeed()
        external
        view
        returns (address)
    {
        return aggregatedDerivativePriceFeed;
    }

    /// @notice Gets the `primitivePriceFeed` variable
    /// @return _primitivePriceFeed The `primitivePriceFeed` variable value
    function getPrimitivePriceFeed()
        external
        view
        returns (address)
    {
        return primitivePriceFeed;
    }

    ///////////////////
    // STATE SETTERS //
    ///////////////////

    /// @notice Set the primitive price feed. Only governance or delegate role can call.
    function setPrimitivePriceFeed(address _primitivePriceFeed)
        external
        onlyGovOrDelegate
    {
        primitivePriceFeed = _primitivePriceFeed;
        emit UpdatePrimitivePriceFeed(_primitivePriceFeed);
    }

    /// @notice Set the aggregated derivative price feed. Only governance or delegate role can call.
    function setAggregatedDerivativePriceFeed(
        address _aggregatedDerivativePriceFeed
    ) external onlyGovOrDelegate {
        aggregatedDerivativePriceFeed = _aggregatedDerivativePriceFeed;
        emit UpdateAggregatedDerivativePriceFeed(
            _aggregatedDerivativePriceFeed
        );
    }
}
