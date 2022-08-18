// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./IPrimitivePriceFeed.sol";
import "./../../access-control/AccessControlMixin.sol";
import "hardhat/console.sol";

contract ChainlinkPriceFeed is IPrimitivePriceFeed, AccessControlMixin {
    event EthUsdAggregatorSet(
        address _prevEthUsdAggregator,
        uint256 _prevEthUsdHeartbeat,
        address _nextEthUsdAggregator,
        uint256 _nextEthUsdHeartbeat
    );

    event PrimitiveAdded(
        address indexed _primitive,
        address _aggregator,
        uint256 _heartbeat,
        RateAsset _rateAsset,
        uint256 _unit
    );

    event BasePeggedAdded(address indexed _basePegged, RateAsset _rateAsset);

    event PrimitiveRemoved(address indexed _primitive);
    event BasePeggedRemoved(address indexed _basePegged);

    event PrimitiveUpdated(
        address indexed _primitive,
        address _prevAggregator,
        address _nextAggregator,
        uint256 _nextHeartbeat
    );

    event StalePrimitiveRemoved(address indexed _primitive);

    enum RateAsset {
        ETH,
        USD
    }

    struct AggregatorInfo {
        address aggregator;
        uint256 heartbeat;
        RateAsset rateAsset;
    }

    struct BasePeggedInfo {
        bool isBasePegged;
        uint256 tokenUnit;
        RateAsset rateAsset;
    }

    uint256 private constant ETH_UNIT = 10**18;
    uint256 private constant BASIC_UNIT = 10**18;
    uint256 private constant USD_UNIT = 10**8;
    uint256 private ethUsdHeartbeat;
    address private ethUsdAggregator;
    mapping(address => AggregatorInfo) private primitiveToAggregatorInfo;
    mapping(address => uint256) private primitiveToUnit;

    mapping(address => BasePeggedInfo) private basePeggedInfos;

    constructor(
        address _ethUsdAggregator,
        uint256 _ethUsdHeartbeat,
        address[] memory _primitives,
        address[] memory _aggregators,
        uint256[] memory _heartbeats,
        RateAsset[] memory _rateAssets,
        address[] memory _basePeggeds,
        RateAsset[] memory _peggedRateAssets,
        address _accessControlProxy
    ) {
        _initAccessControl(_accessControlProxy);

        // 24 hour heartbeat + 1hr buffer
        __setEthUsdAggregator(_ethUsdAggregator, _ethUsdHeartbeat);

        if (_basePeggeds.length > 0) {
            __addBasePeggedInfos(_basePeggeds, _peggedRateAssets);
        }

        if (_primitives.length > 0) {
            __addPrimitives(_primitives, _aggregators, _heartbeats, _rateAssets);
        }
    }

    // EXTERNAL FUNCTIONS

    /// @notice Calculates the value of a base asset in terms of a quote asset (using a canonical rate)
    /// @param _baseAsset The base asset
    /// @param _baseAssetAmount The base asset amount to convert
    /// @param _quoteAsset The quote asset
    /// @return _quoteAssetAmount The equivalent quote asset amount
    /// @return _isValid True if the rates used in calculations are deemed valid
    function calcCanonicalValue(
        address _baseAsset,
        uint256 _baseAssetAmount,
        address _quoteAsset
    ) public view override returns (uint256 _quoteAssetAmount, bool _isValid) {
        // Case where _baseAsset == _quoteAsset is handled by ValueInterpreter

        int256 baseAssetRate = __getLatestRateData(_baseAsset);
        if (baseAssetRate <= 0) {
            return (0, false);
        }

        int256 quoteAssetRate = __getLatestRateData(_quoteAsset);
        if (quoteAssetRate <= 0) {
            return (0, false);
        }

        (_quoteAssetAmount, _isValid) = __calcConversionAmount(
            _baseAsset,
            _baseAssetAmount,
            uint256(baseAssetRate),
            _quoteAsset,
            uint256(quoteAssetRate)
        );

        return (_quoteAssetAmount, _isValid);
    }

    /// @notice Calculates the value of a base asset in terms of a quote asset (using a canonical rate)
    /// @param _baseAsset The base asset
    /// @param _baseAssetAmount The base asset amount to convert
    /// @return _quoteAssetAmount The equivalent quote asset amount (usd 1e8)
    /// @return _isValid True if the rates used in calculations are deemed valid
    function calcValueInUsd(address _baseAsset, uint256 _baseAssetAmount)
        external
        view
        override
        returns (uint256 _quoteAssetAmount, bool _isValid)
    {
        // Case where _baseAsset == _quoteAsset is handled by ValueInterpreter

        int256 baseAssetRate = __getLatestRateData(_baseAsset);
        if (baseAssetRate <= 0) {
            return (0, false);
        }

        (_quoteAssetAmount, _isValid) = __calcConversionAmountInUsd(
            _baseAsset,
            _baseAssetAmount,
            uint256(baseAssetRate)
        );

        return (_quoteAssetAmount, _isValid);
    }

    /// @notice Gets the unit variable value for a primitive
    /// @return _unit The unit variable value
    function getAssetUnit(address _asset) public view override returns (uint256 _unit) {
        return getUnitForPrimitive(_asset);
    }

    /// @notice Checks whether an asset is a supported primitive of the price feed
    /// @param _asset The asset to check
    /// @return _isSupported True if the asset is a supported primitive
    function isSupportedAsset(address _asset) external view override returns (bool _isSupported) {
        return
            basePeggedInfos[_asset].isBasePegged ||
            primitiveToAggregatorInfo[_asset].aggregator != address(0);
    }

    /// @notice Sets the `ehUsdAggregator` variable value
    /// @param _nextEthUsdAggregator The `ehUsdAggregator` value to set
    function setEthUsdAggregator(address _nextEthUsdAggregator, uint256 _nextEthUsdHeartbeat)
        external
        onlyGovOrDelegate
    {
        __setEthUsdAggregator(_nextEthUsdAggregator, _nextEthUsdHeartbeat);
    }

    // PRIVATE FUNCTIONS

    /// @dev Helper to convert an amount from a _baseAsset to a _quoteAsset
    function __calcConversionAmount(
        address _baseAsset,
        uint256 _baseAssetAmount,
        uint256 _baseAssetRate,
        address _quoteAsset,
        uint256 _quoteAssetRate
    ) private view returns (uint256 quoteAssetAmount_, bool isValid_) {
        RateAsset _baseAssetRateAsset = getRateAssetForPrimitive(_baseAsset);
        RateAsset _quoteAssetRateAsset = getRateAssetForPrimitive(_quoteAsset);
        uint256 _baseAssetUnit = getUnitForPrimitive(_baseAsset);
        uint256 _quoteAssetUnit = getUnitForPrimitive(_quoteAsset);

        // If rates are both in ETH or both in USD
        if (_baseAssetRateAsset == _quoteAssetRateAsset) {
            return (
                __calcConversionAmountSameRateAsset(
                    _baseAssetAmount,
                    _baseAssetUnit,
                    _baseAssetRate,
                    _quoteAssetUnit,
                    _quoteAssetRate
                ),
                true
            );
        }

        (, int256 _ethPerUsdRate, , uint256 _ethPerUsdRateLastUpdatedAt, ) = AggregatorV3Interface(
            ethUsdAggregator
        ).latestRoundData();
        if (_ethPerUsdRate <= 0) {
            return (0, false);
        }
        __validateRateIsNotStale(ethUsdAggregator, _ethPerUsdRateLastUpdatedAt, ethUsdHeartbeat);

        // If _baseAsset's rate is in ETH and _quoteAsset's rate is in USD
        if (_baseAssetRateAsset == RateAsset.ETH) {
            return (
                __calcConversionAmountEthRateAssetToUsdRateAsset(
                    _baseAssetAmount,
                    _baseAssetUnit,
                    _baseAssetRate,
                    _quoteAssetUnit,
                    _quoteAssetRate,
                    uint256(_ethPerUsdRate)
                ),
                true
            );
        }

        // If _baseAsset's rate is in USD and _quoteAsset's rate is in ETH
        return (
            __calcConversionAmountUsdRateAssetToEthRateAsset(
                _baseAssetAmount,
                _baseAssetUnit,
                _baseAssetRate,
                _quoteAssetUnit,
                _quoteAssetRate,
                uint256(_ethPerUsdRate)
            ),
            true
        );
    }

    /// @dev Helper to convert an amount from a _baseAsset to a _usdAsset
    function __calcConversionAmountInUsd(
        address _baseAsset,
        uint256 _baseAssetAmount,
        uint256 _baseAssetRate
    ) private view returns (uint256 _usdAssetAmount, bool _isValid) {
        RateAsset _baseAssetRateAsset = getRateAssetForPrimitive(_baseAsset);

        uint256 _baseAssetUnit = getUnitForPrimitive(_baseAsset);
        uint256 _quoteAssetUnit = BASIC_UNIT;
        uint256 _quoteAssetRate = USD_UNIT;

        // If base asset rates are in USD
        if (_baseAssetRateAsset == RateAsset.USD) {
            return (
                __calcConversionAmountSameRateAsset(
                    _baseAssetAmount,
                    _baseAssetUnit,
                    _baseAssetRate,
                    _quoteAssetUnit,
                    _quoteAssetRate
                ),
                true
            );
        }

        (, int256 _ethPerUsdRate, , uint256 _ethPerUsdRateLastUpdatedAt, ) = AggregatorV3Interface(
            ethUsdAggregator
        ).latestRoundData();
        if (_ethPerUsdRate <= 0) {
            return (0, false);
        }
        __validateRateIsNotStale(ethUsdAggregator, _ethPerUsdRateLastUpdatedAt, ethUsdHeartbeat);

        // If _baseAsset's rate is in ETH
        return (
            __calcConversionAmountEthRateAssetToUsdRateAsset(
                _baseAssetAmount,
                _baseAssetUnit,
                _baseAssetRate,
                _quoteAssetUnit,
                _quoteAssetRate,
                uint256(_ethPerUsdRate)
            ),
            true
        );
    }

    /// @dev Helper to convert amounts where the base asset has an ETH rate and the quote asset has a USD rate
    function __calcConversionAmountEthRateAssetToUsdRateAsset(
        uint256 _baseAssetAmount,
        uint256 _baseAssetUnit,
        uint256 _baseAssetRate,
        uint256 _quoteAssetUnit,
        uint256 _quoteAssetRate,
        uint256 _ethPerUsdRate
    ) private pure returns (uint256 _quoteAssetAmount) {
        // Only allows two consecutive multiplication operations to avoid potential overflow.
        // Intermediate step needed to resolve stack-too-deep error.
        uint256 _intermediateStep = (_baseAssetAmount * _baseAssetRate * _ethPerUsdRate) / ETH_UNIT;

        return (_intermediateStep * _quoteAssetUnit) / _baseAssetUnit / _quoteAssetRate;
    }

    /// @dev Helper to convert amounts where base and quote assets both have ETH rates or both have USD rates
    function __calcConversionAmountSameRateAsset(
        uint256 _baseAssetAmount,
        uint256 _baseAssetUnit,
        uint256 _baseAssetRate,
        uint256 _quoteAssetUnit,
        uint256 _quoteAssetRate
    ) private pure returns (uint256 _quoteAssetAmount) {
        // Only allows two consecutive multiplication operations to avoid potential overflow
        return (_baseAssetAmount * _baseAssetRate * _quoteAssetUnit) / (_baseAssetUnit * _quoteAssetRate);
    }

    /// @dev Helper to convert amounts where the base asset has a USD rate and the quote asset has an ETH rate
    function __calcConversionAmountUsdRateAssetToEthRateAsset(
        uint256 _baseAssetAmount,
        uint256 _baseAssetUnit,
        uint256 _baseAssetRate,
        uint256 _quoteAssetUnit,
        uint256 _quoteAssetRate,
        uint256 _ethPerUsdRate
    ) private pure returns (uint256 _quoteAssetAmount) {
        // Only allows two consecutive multiplication operations to avoid potential overflow
        // Intermediate step needed to resolve stack-too-deep error.
        uint256 _intermediateStep = (_baseAssetAmount * _baseAssetRate * _quoteAssetUnit) /
            _ethPerUsdRate;

        return (_intermediateStep * ETH_UNIT) / _baseAssetUnit / _quoteAssetRate;
    }

    /// @dev Helper to get the latest rate for a given primitive
    function __getLatestRateData(address _primitive) private view returns (int256) {
        if (basePeggedInfos[_primitive].isBasePegged) {
            if (basePeggedInfos[_primitive].rateAsset == RateAsset.ETH) {
                return int256(ETH_UNIT);
            } else {
                return int256(USD_UNIT);
            }
        }

        AggregatorInfo memory _aggregatorInfo = primitiveToAggregatorInfo[_primitive];
        require(
            _aggregatorInfo.aggregator != address(0),
            "__getLatestRateData: Primitive does not exist"
        );
        (, int256 _rate, , uint256 _rateUpdatedAt, ) = AggregatorV3Interface(_aggregatorInfo.aggregator)
            .latestRoundData();
        __validateRateIsNotStale(_aggregatorInfo.aggregator, _rateUpdatedAt, _aggregatorInfo.heartbeat);

        return _rate;
    }

    /// @dev Helper to set the `ethUsdAggregator` value
    function __setEthUsdAggregator(address _nextEthUsdAggregator, uint256 _nextEthUsdHeartbeat) private {
        address _prevEthUsdAggregator = ethUsdAggregator;
        uint256 _prevEthUsdHeartbeat = ethUsdHeartbeat;
        require(
            _nextEthUsdAggregator != _prevEthUsdAggregator ||
                _nextEthUsdHeartbeat != _prevEthUsdHeartbeat,
            "__setEthUsdAggregator: Value already set"
        );

        __validateAggregator(_nextEthUsdAggregator, _nextEthUsdHeartbeat);

        ethUsdAggregator = _nextEthUsdAggregator;
        ethUsdHeartbeat = _nextEthUsdHeartbeat;

        emit EthUsdAggregatorSet(
            _prevEthUsdAggregator,
            _prevEthUsdHeartbeat,
            _nextEthUsdAggregator,
            _nextEthUsdHeartbeat
        );
    }

    /////////////////////////
    // PRIMITIVES REGISTRY //
    /////////////////////////

    function addBasePeggedInfos(address[] calldata _peggedTokens, RateAsset[] calldata _rateAssets)
        external
        onlyGovOrDelegate
    {
        require(_peggedTokens.length > 0, "addBasePeggedInfos: _peggedTokens cannot be empty");

        __addBasePeggedInfos(_peggedTokens, _rateAssets);
    }

    function removeBasePeggedInfos(address[] calldata _peggedTokens) external onlyGovOrDelegate {
        require(_peggedTokens.length > 0, "removeBasePeggedInfos: _peggedTokens cannot be empty");

        for (uint256 i = 0; i < _peggedTokens.length; i++) {
            require(
                basePeggedInfos[_peggedTokens[i]].isBasePegged,
                "removeBasePeggedInfos: _peggedTokens not yet added"
            );

            delete basePeggedInfos[_peggedTokens[i]];

            emit BasePeggedRemoved(_peggedTokens[i]);
        }
    }

    /// @notice Adds a list of primitives with the given aggregator and rateAsset values
    /// @param _primitives The primitives to add
    /// @param _aggregators The ordered aggregators corresponding to the list of _primitives
    /// @param _rateAssets The ordered rate assets corresponding to the list of _primitives
    function addPrimitives(
        address[] calldata _primitives,
        address[] calldata _aggregators,
        uint256[] calldata _heartbeats,
        RateAsset[] calldata _rateAssets
    ) external onlyGovOrDelegate {
        require(_primitives.length > 0, "addPrimitives: _primitives cannot be empty");

        __addPrimitives(_primitives, _aggregators, _heartbeats, _rateAssets);
    }

    /// @notice Removes a list of primitives from the feed
    /// @param _primitives The primitives to remove
    function removePrimitives(address[] calldata _primitives) external onlyGovOrDelegate {
        require(_primitives.length > 0, "removePrimitives: _primitives cannot be empty");

        for (uint256 i = 0; i < _primitives.length; i++) {
            require(
                primitiveToAggregatorInfo[_primitives[i]].aggregator != address(0),
                "removePrimitives: Primitive not yet added"
            );

            delete primitiveToAggregatorInfo[_primitives[i]];
            delete primitiveToUnit[_primitives[i]];

            emit PrimitiveRemoved(_primitives[i]);
        }
    }

    /// @notice Updates the aggregators for given primitives
    /// @param _primitives The primitives to update
    /// @param _aggregators The ordered aggregators corresponding to the list of _primitives
    function updatePrimitives(
        address[] calldata _primitives,
        address[] calldata _aggregators,
        uint256[] calldata _heartbeats
    ) external onlyGovOrDelegate {
        require(_primitives.length > 0, "updatePrimitives: _primitives cannot be empty");
        require(
            _primitives.length == _aggregators.length,
            "updatePrimitives: Unequal _primitives and _aggregators array lengths"
        );

        for (uint256 i = 0; i < _primitives.length; i++) {
            address _prevAggregator = primitiveToAggregatorInfo[_primitives[i]].aggregator;
            require(_prevAggregator != address(0), "updatePrimitives: Primitive not yet added");

            __validateAggregator(_aggregators[i], _heartbeats[i]);

            primitiveToAggregatorInfo[_primitives[i]].aggregator = _aggregators[i];
            primitiveToAggregatorInfo[_primitives[i]].heartbeat = _heartbeats[i];

            emit PrimitiveUpdated(_primitives[i], _prevAggregator, _aggregators[i], _heartbeats[i]);
        }
    }

    function __validateRateIsNotStale(
        address _aggregator,
        uint256 _latestUpdatedAt,
        uint256 _heartbeat
    ) private view {
        require(
            _latestUpdatedAt >= block.timestamp - _heartbeat,
            string(
                abi.encodePacked(
                    "__validateRateIsNotStale: Stale rate detected ",
                    Strings.toHexString(uint160(_aggregator), 20)
                )
            )
        );
    }

    /// @dev Helper to add base Pegged token to the feed
    function __addBasePeggedInfos(address[] memory _peggedTokens, RateAsset[] memory _rateAssets)
        private
    {
        require(
            _peggedTokens.length == _rateAssets.length,
            "__addBasePeggedInfos: Unequal _peggedTokens and _rateAssets array lengths"
        );

        for (uint256 i = 0; i < _peggedTokens.length; i++) {
            uint256 _tokenUnit = 10**uint256(ERC20(_peggedTokens[i]).decimals());

            basePeggedInfos[_peggedTokens[i]] = BasePeggedInfo({
                isBasePegged: true,
                tokenUnit: _tokenUnit,
                rateAsset: _rateAssets[i]
            });

            emit BasePeggedAdded(_peggedTokens[i], _rateAssets[i]);
        }
    }

    /// @dev Helper to add primitives to the feed
    function __addPrimitives(
        address[] memory _primitives,
        address[] memory _aggregators,
        uint256[] memory _heartbeats,
        RateAsset[] memory _rateAssets
    ) private {
        require(
            _primitives.length == _aggregators.length,
            "__addPrimitives: Unequal _primitives and _aggregators array lengths"
        );
        require(
            _primitives.length == _rateAssets.length,
            "__addPrimitives: Unequal _primitives and _rateAssets array lengths"
        );
        require(
            _primitives.length == _heartbeats.length,
            "__addPrimitives: Unequal _primitives and _heartbeats array lengths"
        );

        for (uint256 i = 0; i < _primitives.length; i++) {
            require(
                primitiveToAggregatorInfo[_primitives[i]].aggregator == address(0),
                "__addPrimitives: Value already set"
            );

            __validateAggregator(_aggregators[i], _heartbeats[i]);

            primitiveToAggregatorInfo[_primitives[i]] = AggregatorInfo({
                aggregator: _aggregators[i],
                heartbeat: _heartbeats[i],
                rateAsset: _rateAssets[i]
            });

            // Store the amount that makes up 1 unit given the asset's decimals
            uint256 _unit = 10**uint256(ERC20(_primitives[i]).decimals());
            primitiveToUnit[_primitives[i]] = _unit;

            emit PrimitiveAdded(_primitives[i], _aggregators[i], _heartbeats[i], _rateAssets[i], _unit);
        }
    }

    /// @dev Helper to validate an aggregator by checking its return values for the expected interface
    function __validateAggregator(address _aggregator, uint256 _heartbeat) private view {
        (, int256 _answer, , uint256 _updatedAt, ) = AggregatorV3Interface(_aggregator).latestRoundData();
        require(_answer > 0, "__validateAggregator: No rate detected");
        __validateRateIsNotStale(_aggregator, _updatedAt, _heartbeat);
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the aggregatorInfo variable value for a primitive
    /// @param _primitive The primitive asset for which to get the aggregatorInfo value
    /// @return _aggregatorInfo The aggregatorInfo value
    function getAggregatorInfoForPrimitive(address _primitive)
        external
        view
        returns (AggregatorInfo memory _aggregatorInfo)
    {
        return primitiveToAggregatorInfo[_primitive];
    }

    /// @notice Gets the `ethUsdAggregator` variable value
    /// @return _ethUsdAggregator The `ethUsdAggregator` variable value
    function getEthUsdAggregator() external view returns (address _ethUsdAggregator) {
        return ethUsdAggregator;
    }

    /// @notice Gets the rateAsset variable value for a primitive
    /// @return _rateAsset The rateAsset variable value
    /// @dev This isn't strictly necessary as WETH_TOKEN will be undefined and thus
    /// the RateAsset will be the 0-position of the enum (i.e. ETH), but it makes the
    /// behavior more explicit
    function getRateAssetForPrimitive(address _primitive) public view returns (RateAsset _rateAsset) {
        if (basePeggedInfos[_primitive].isBasePegged) {
            return basePeggedInfos[_primitive].rateAsset;
        }

        return primitiveToAggregatorInfo[_primitive].rateAsset;
    }

    /// @notice Gets the unit variable value for a primitive
    /// @return _unit The unit variable value
    function getUnitForPrimitive(address _primitive) public view returns (uint256 _unit) {
        if (basePeggedInfos[_primitive].isBasePegged) {
            return basePeggedInfos[_primitive].tokenUnit;
        }

        return primitiveToUnit[_primitive];
    }
}
