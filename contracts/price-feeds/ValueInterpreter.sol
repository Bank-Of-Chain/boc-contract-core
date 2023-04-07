// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./derivatives/IAggregatedDerivativePriceFeed.sol";
import "./derivatives/IDerivativePriceFeed.sol";
import "./primitives/IPrimitivePriceFeed.sol";
import "./custom/ICustomPriceFeedAggregator.sol";
import "./../access-control/AccessControlMixin.sol";
import "./IValueInterpreter.sol";

/// @title ValueInterpreter Contract
/// @notice Interprets price feeds to provide covert value between asset pairs
/// @dev This contract contains several 'live' value calculations, which for this release are simply
/// aliases to their 'canonical' value counterparts since the only primitive price feed (Chainlink)
/// is immutable in this contract and only has one type of value. Including the 'live' versions of
/// functions only serves as a placeholder for infrastructural components and plugins (e.g., policies)
/// to explicitly define the types of values that they should (and will) be using in a future release.
/// @author Bank of Chain Protocol Inc
contract ValueInterpreter is IValueInterpreter, AccessControlMixin {

    /// @param _chainlinkPriceFeed The address of the new primitive price feed contract
    event UpdateChainPriceFeed(address _chainlinkPriceFeed);

    /// @param _uniswapV3PriceFeed The price feed address of the new aggregated derivative
    event UpdateUniswapV3PriceFeed(address _uniswapV3PriceFeed);/// @param _uniswapV3PriceFeed The price feed address of the new aggregated derivative

    /// @param _customPriceFeedAggregator The price feed address of the new aggregated derivative
    event UpdateCustomPriceFeedAggregator(address _customPriceFeedAggregator);

    address private chainlinkPriceFeed;
    address private uniswapV3PriceFeed;
    address private customPriceFeedAggregator;

    constructor(address _chainlinkPriceFeed, address _uniswapV3PriceFeed,address _customPriceFeedAggregator, address _accessControlProxy) {
        uniswapV3PriceFeed = _uniswapV3PriceFeed;
        chainlinkPriceFeed = _chainlinkPriceFeed;
        customPriceFeedAggregator = _customPriceFeedAggregator;
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
            IPrimitivePriceFeed(chainlinkPriceFeed).isSupportedAsset(_quoteAsset) ||
                IPrimitivePriceFeed(uniswapV3PriceFeed).isSupportedAsset(_quoteAsset),
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
    function calcCanonicalAssetsTotalValueInEth(
        address[] calldata _baseAssets,
        uint256[] calldata _amounts,
        address _quoteAsset
    ) external view override returns (uint256 _value) {
        require(
            _baseAssets.length == _amounts.length,
            "calcCanonicalAssetsTotalValueInEth: Arrays unequal lengths"
        );
        require(
            IPrimitivePriceFeed(chainlinkPriceFeed).isSupportedAsset(_quoteAsset) ||
                IPrimitivePriceFeed(uniswapV3PriceFeed).isSupportedAsset(_quoteAsset),
            string(
                abi.encodePacked(
                    "calcCanonicalAssetsTotalValueInEth: Unsupported _quoteAsset ",
                    Strings.toHexString(uint160(_quoteAsset), 20)
                )
            )
        );

        bool _isValid = true;
        for (uint256 i = 0; i < _baseAssets.length; i++) {
            (uint256 _assetValue, bool _assetValueIsValid) = __calcAssetValueInEth(
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
    function calcCanonicalAssetValueInEth(
        address _baseAsset,
        uint256 _amount,
        address _quoteAsset
    ) external view override returns (uint256 _value) {
        if (_baseAsset == _quoteAsset || _amount == 0) {
            return _amount;
        }
        bool _isValid;
        (_value, _isValid) = __calcAssetValueInEth(_baseAsset, _amount, _quoteAsset);
        require(_isValid, "Invalid rate");
        return _value;
    }

    /// @inheritdoc IValueInterpreter
    function calcCanonicalAssetValueInUsd(
        address _baseAsset,
        uint256 _amount
    ) external view override returns (uint256 _value) {
        if (_amount == 0) {
            return _amount;
        }
        bool _isValid;
        (_value, _isValid) = __calcAssetValueInUsd(_baseAsset, _amount);
        require(_isValid, "Invalid rate");
        return _value;
    }

    /// @inheritdoc IValueInterpreter
    function calcCanonicalAssetValueInEth(
        address _baseAsset,
        uint256 _amount
    ) external view override returns (uint256 _value) {
        if (_amount == 0) {
            return _amount;
        }
        bool _isValid;
        (_value, _isValid) = __calcAssetValueInEth(_baseAsset, _amount);
        require(_isValid, "Invalid rate");
        return _value;
    }

    /// @inheritdoc IValueInterpreter
    function price(address _baseAsset) external view override returns (uint256 _value) {
        if (ICustomPriceFeedAggregator(customPriceFeedAggregator).isSupportedAsset(_baseAsset)) {
            bool _isValid;
            (_value, _isValid) = ICustomPriceFeedAggregator(customPriceFeedAggregator).calcValueInUsd(
                _baseAsset,
                ICustomPriceFeedAggregator(customPriceFeedAggregator).getAssetUnit(_baseAsset)
            );
            require(_isValid, "Invalid rate");
            return _value;
        }
        // Handle case that asset is a primitive
        if (IPrimitivePriceFeed(chainlinkPriceFeed).isSupportedAsset(_baseAsset)) {
            bool _isValid;
            (_value, _isValid) = IPrimitivePriceFeed(chainlinkPriceFeed).calcValueInUsd(
                _baseAsset,
                IPrimitivePriceFeed(chainlinkPriceFeed).getAssetUnit(_baseAsset)
            );
            require(_isValid, "Invalid rate");
            return _value;
        }
        if (IPrimitivePriceFeed(uniswapV3PriceFeed).isSupportedAsset(_baseAsset)) {
            bool _isValid;
            (_value, _isValid) = IPrimitivePriceFeed(uniswapV3PriceFeed).calcValueInUsd(
                _baseAsset,
                IPrimitivePriceFeed(uniswapV3PriceFeed).getAssetUnit(_baseAsset)
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

    /// @inheritdoc IValueInterpreter
    function priceInEth(address _baseAsset) external view override returns (uint256 _value) {
        if (ICustomPriceFeedAggregator(customPriceFeedAggregator).isSupportedAsset(_baseAsset)) {
            bool _isValid;
            (_value, _isValid) = ICustomPriceFeedAggregator(customPriceFeedAggregator).calcValueInEth(
                _baseAsset,
                ICustomPriceFeedAggregator(customPriceFeedAggregator).getAssetUnit(_baseAsset)
            );
            require(_isValid, "Invalid rate");
            return _value;
        }
        // Handle case that asset is a primitive
        if (IPrimitivePriceFeed(chainlinkPriceFeed).isSupportedAsset(_baseAsset)) {
            bool _isValid;
            (_value, _isValid) = IPrimitivePriceFeed(chainlinkPriceFeed).calcValueInEth(
                _baseAsset,
                IPrimitivePriceFeed(chainlinkPriceFeed).getAssetUnit(_baseAsset)
            );
            require(_isValid, "Invalid rate");
            return _value;
        }
        if (IPrimitivePriceFeed(uniswapV3PriceFeed).isSupportedAsset(_baseAsset)) {
            bool _isValid;
            (_value, _isValid) = IPrimitivePriceFeed(uniswapV3PriceFeed).calcValueInEth(
                _baseAsset,
                IPrimitivePriceFeed(uniswapV3PriceFeed).getAssetUnit(_baseAsset)
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
    function __calcAssetValueInUsd(
        address _baseAsset,
        uint256 _amount
    ) private view returns (uint256 _value, bool _isValid) {
        if (_amount == 0) {
            return (_amount, true);
        }

        // Handle case that asset with customPriceFeed
        if (ICustomPriceFeedAggregator(customPriceFeedAggregator).isSupportedAsset(_baseAsset)) {
            return
                ICustomPriceFeedAggregator(customPriceFeedAggregator).calcValueInUsd(_baseAsset, _amount);
        }
        // Handle case that asset with chainlink
        if (IPrimitivePriceFeed(chainlinkPriceFeed).isSupportedAsset(_baseAsset)) {
            return IPrimitivePriceFeed(chainlinkPriceFeed).calcValueInUsd(_baseAsset, _amount);
        }

        // Handle case that asset with uniswapV3
        if (IPrimitivePriceFeed(uniswapV3PriceFeed).isSupportedAsset(_baseAsset)) {
            return IPrimitivePriceFeed(uniswapV3PriceFeed).calcValueInUsd(_baseAsset, _amount);
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
    function __calcAssetValueInEth(
        address _baseAsset,
        uint256 _amount
    ) private view returns (uint256 _value, bool _isValid) {
        if (_amount == 0) {
            return (_amount, true);
        }
        // Handle case that asset with customPriceFeed
        if (ICustomPriceFeedAggregator(customPriceFeedAggregator).isSupportedAsset(_baseAsset)) {
            return
                ICustomPriceFeedAggregator(customPriceFeedAggregator).calcValueInEth(_baseAsset, _amount);
        }

        // Handle case that asset with chainlink
        if (IPrimitivePriceFeed(chainlinkPriceFeed).isSupportedAsset(_baseAsset)) {
            return IPrimitivePriceFeed(chainlinkPriceFeed).calcValueInEth(_baseAsset, _amount);
        }

        // Handle case that asset with uniswapV3
        if (IPrimitivePriceFeed(uniswapV3PriceFeed).isSupportedAsset(_baseAsset)) {
            return IPrimitivePriceFeed(uniswapV3PriceFeed).calcValueInEth(_baseAsset, _amount);
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

    function _getQuoteAssetUnit(address _quoteAsset) private view returns(uint256){
        // Handle case that asset with customPriceFeed
        if (ICustomPriceFeedAggregator(customPriceFeedAggregator).isSupportedAsset(_quoteAsset)) {
            return
                ICustomPriceFeedAggregator(customPriceFeedAggregator).getAssetUnit(_quoteAsset);
        }

        // Handle case that asset with chainlink
        if (IPrimitivePriceFeed(chainlinkPriceFeed).isSupportedAsset(_quoteAsset)) {
            return IPrimitivePriceFeed(chainlinkPriceFeed).getAssetUnit(_quoteAsset);
        }

        // Handle case that asset with uniswapV3
        if (IPrimitivePriceFeed(uniswapV3PriceFeed).isSupportedAsset(_quoteAsset)) {
            return IPrimitivePriceFeed(uniswapV3PriceFeed).getAssetUnit(_quoteAsset);
        }

        revert(
            string(
                abi.encodePacked(
                    "_getQuoteAssetUnit: Unsupported _quoteAsset ",
                    Strings.toHexString(uint160(_quoteAsset), 20)
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

       (uint256 _baseTotalValueInUsd,bool _baseIsValid)  = __calcAssetValueInUsd(_baseAsset,_amount);
       uint256 _quoteAssetOneUnit = _getQuoteAssetUnit(_quoteAsset);
       (uint256 _priceInUsdPerQuote, bool _quoteIsValid) = __calcAssetValueInUsd(_quoteAsset,_quoteAssetOneUnit);

        if (_baseIsValid && _quoteIsValid) {
            return (_baseTotalValueInUsd * _quoteAssetOneUnit / _priceInUsdPerQuote , true);
        }
        return (0, false);
    }

    /// @dev Helper to differentially calculate an asset value
    /// based on if it is a primitive or derivative asset.
    function __calcAssetValueInEth(
        address _baseAsset,
        uint256 _amount,
        address _quoteAsset
    ) private view returns (uint256 _value, bool _isValid) {
        if (_baseAsset == _quoteAsset || _amount == 0) {
            return (_amount, true);
        }

       (uint256 _baseTotalValueInEth,bool _baseIsValid)  = __calcAssetValueInEth(_baseAsset,_amount);
       uint256 _quoteAssetOneUnit = _getQuoteAssetUnit(_quoteAsset);
       (uint256 _priceInEthPerQuote, bool _quoteIsValid) = __calcAssetValueInEth(_quoteAsset,_quoteAssetOneUnit);

        if (_baseIsValid && _quoteIsValid) {
            return (_baseTotalValueInEth * _quoteAssetOneUnit / _priceInEthPerQuote, true);
        }
        return (0, false);
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the uniswapV3Price variable
    function getUniswapV3PriceFeed() external view returns (address) {
        return uniswapV3PriceFeed;
    }

    /// @notice Gets the chainlinkPriceFeed variable
    function getChainlinkPriceFeed() external view returns (address) {
        return chainlinkPriceFeed;
    }

    /// @notice Gets the customPriceFeedAggregator variable
    function getCustomPriceFeedAggregator() external view returns (address) {
        return customPriceFeedAggregator;
    }

    ///////////////////
    // STATE SETTERS //
    ///////////////////

    /// @notice Set the primitive price feed. Only governance or delegate role can call.
    /// @param _chainlinkPriceFeed The address of the new primitive price feed contract
    function setChainlinkPriceFeed(address _chainlinkPriceFeed) external onlyGovOrDelegate {
        chainlinkPriceFeed = _chainlinkPriceFeed;
        emit UpdateChainPriceFeed(_chainlinkPriceFeed);
    }

    /// @notice Set the aggregated derivative price feed. Only governance or delegate role can call.
    /// @param _uniswapV3PriceFeed The price feed address of the new aggregated derivative
    function setUniswapV3PriceFeed(address _uniswapV3PriceFeed) external onlyGovOrDelegate {
        uniswapV3PriceFeed = _uniswapV3PriceFeed;
        emit UpdateUniswapV3PriceFeed(_uniswapV3PriceFeed);
    }

    /// @notice Set the aggregated derivative price feed. Only governance or delegate role can call.
    /// @param _customPriceFeedAggregator The price feed address of the new aggregated derivative
    function setCustomPriceFeedAggregator(address _customPriceFeedAggregator) external onlyGovOrDelegate {
        customPriceFeedAggregator = _customPriceFeedAggregator;
        emit UpdateCustomPriceFeedAggregator(_customPriceFeedAggregator);
    }
}
