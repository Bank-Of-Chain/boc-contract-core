// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "./IPrimitivePriceFeed.sol";
import "./../../access-control/AccessControlMixin.sol";
import "../../library/NativeToken.sol";

/// @title UniswapV3 TWAP
/// @notice The price feed is from the UniswapV3，
///         the quote asset should be ETH or WETH.
/// @author Bank of Chain Protocol Inc
contract UniswapV3PriceFeed is IPrimitivePriceFeed, AccessControlMixin {
    /// @param _primitive The primitive asset added
    /// @param _pool The pool of uniswapV3
    /// @param _duration The duration of TWAP
    event PrimitiveAdded(address indexed _primitive, address _pool, uint32 _duration);
    /// @param _primitive The primitive asset removed
    event PrimitiveRemoved(address indexed _primitive);

    struct AggregatorInfo {
        // address quoteToken;
        address pool; // v3 pool address
        uint32 duration; // time weighted by
    }

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    mapping(address => AggregatorInfo) private primitiveToAggregatorInfo;
    mapping(address => uint256) private primitiveToUnit;

    address ethUsdAggregator;

    constructor(
        address _accessControlProxy,
        address _ethUsdAggregator,
        address[] memory _primitives,
        address[] memory _pools,
        uint32[] memory _durations
    ) {
        ethUsdAggregator = _ethUsdAggregator;
        _initAccessControl(_accessControlProxy);
        __addPrimitives(_primitives, _pools, _durations);
    }

    function calcCanonicalValue(
        address _baseAsset,
        uint256 _baseAssetAmount,
        address _quoteAsset
    ) external view override returns (uint256 _quoteAssetAmount, bool _isValid) {
        if (_quoteAsset == NativeToken.NATIVE_TOKEN || _quoteAsset == WETH) {
            return calcValueInEth(_baseAsset, _baseAssetAmount);
        }

        (uint256 _baseAssetValueInEth, bool _baseAssetIsValid) = calcValueInEth(
            _baseAsset,
            _baseAssetAmount
        );
        if (!_baseAssetIsValid) {
            revert(
                string(
                    abi.encodePacked(
                        "__calcAssetValue: Unsupported _baseAsset ",
                        Strings.toHexString(uint160(_baseAsset), 20)
                    )
                )
            );
        }

        (uint256 _quoteAssetValueInEth, bool _quoteAssetIsValid) = calcValueInEth(_quoteAsset, 1 ether);
        if (!_quoteAssetIsValid) {
            revert(
                string(
                    abi.encodePacked(
                        "__calcAssetValue: Unsupported _quoteAsset ",
                        Strings.toHexString(uint160(_quoteAsset), 20)
                    )
                )
            );
        }

        return (
            (_baseAssetValueInEth * primitiveToUnit[_quoteAsset] * _baseAssetAmount) /
                _quoteAssetValueInEth /
                primitiveToUnit[_baseAsset],
            true
        );
    }

    function calcValueInUsd(
        address _baseAsset,
        uint256 _baseAssetAmount
    ) external view override returns (uint256 _quoteAssetAmount, bool _isValid) {
        (uint256 _priceInEth, bool __isValid) = calcValueInEth(_baseAsset, _baseAssetAmount);
        if (!__isValid) {
            return (0, false);
        }
        (, int256 _ethPriceInUsd, , , ) = AggregatorV3Interface(ethUsdAggregator).latestRoundData();
        return ((_priceInEth * uint(_ethPriceInUsd)) / 1e8, true);
    }

    function calcValueInEth(
        address _baseAsset,
        uint256 _baseAssetAmount
    ) public view override returns (uint256 _quoteAssetAmount, bool _isValid) {
        if (_baseAsset == NativeToken.NATIVE_TOKEN || _baseAsset == WETH) {
            return (_baseAssetAmount * 1e18, true);
        }

        AggregatorInfo memory info = primitiveToAggregatorInfo[_baseAsset];
        if (info.pool == address(0)) {
            return (0, false);
        }
        return (
            (__getTwapPrice(info.pool, info.duration) * _baseAssetAmount) / primitiveToUnit[_baseAsset],
            true
        );
    }

    function getAssetUnit(address _asset) external view override returns (uint256 _unit) {
        return primitiveToUnit[_asset];
    }

    function isSupportedAsset(address _asset) external view override returns (bool _isSupported) {
        return primitiveToAggregatorInfo[_asset].pool != address(0);
    }

    /// @notice Adds a list of primitives with the given aggregator and rateAsset values
    /// @param _primitives The primitives to add
    /// @param _pools The pool of uniswapV3
    /// @param _durations The duration of TWAP
    /// Requirements: only governance or delegate role can call
    function addPrimitives(
        address[] memory _primitives,
        address[] memory _pools,
        uint32[] memory _durations
    ) external onlyGovOrDelegate {
        require(_primitives.length > 0, "addPrimitives: _primitives cannot be empty");

        __addPrimitives(_primitives, _pools, _durations);
    }

    /// @notice Removes a list of primitives from the feed
    /// @param _primitives The primitives to remove
    /// Requirements: only governance or delegate role can call
    /// Emits a {PrimitiveRemoved} event
    function removePrimitives(address[] calldata _primitives) external onlyGovOrDelegate {
        require(_primitives.length > 0, "removePrimitives: _primitives cannot be empty");

        for (uint256 i = 0; i < _primitives.length; i++) {
            require(
                primitiveToAggregatorInfo[_primitives[i]].pool != address(0),
                "removePrimitives: Primitive not yet added"
            );

            delete primitiveToAggregatorInfo[_primitives[i]];
            delete primitiveToUnit[_primitives[i]];

            emit PrimitiveRemoved(_primitives[i]);
        }
    }

    /// @dev Helper to add primitives to the feed
    function __addPrimitives(
        address[] memory _primitives,
        address[] memory _pools,
        uint32[] memory _durations
    ) private {
        require(
            _primitives.length == _pools.length,
            "__addPrimitives: Unequal _primitives and _aggregators array lengths"
        );
        require(
            _primitives.length == _durations.length,
            "__addPrimitives: Unequal _primitives and _rateAssets array lengths"
        );

        for (uint256 i = 0; i < _primitives.length; i++) {
            require(
                primitiveToAggregatorInfo[_primitives[i]].pool == address(0),
                "__addPrimitives: Value already set"
            );

            __validateAggregator(_primitives[i], _pools[i], _durations[i]);

            primitiveToAggregatorInfo[_primitives[i]] = AggregatorInfo({
                pool: _pools[i],
                duration: _durations[i]
            });

            // Store the amount that makes up 1 unit given the asset's decimals
            uint256 _unit = 10 ** uint256(ERC20(_primitives[i]).decimals());
            primitiveToUnit[_primitives[i]] = _unit;

            emit PrimitiveAdded(_primitives[i], _pools[i], _durations[i]);
        }
    }

    /// @notice Gets the TWAP Price of `_pool` on `_twapDuration`
    /// @param _pool One pool address of uniswap V3
    /// @param _twapDuration The time duration to get price
    /// @return The TWAP Price of `_pool` on `_twapDuration`
    function __getTwapPrice(address _pool, uint32 _twapDuration) internal view returns (uint256) {
        uint32[] memory _secondsAgo = new uint32[](2);
        _secondsAgo[0] = _twapDuration;
        _secondsAgo[1] = 0;

        (int56[] memory _tickCumulatives, ) = IUniswapV3Pool(_pool).observe(_secondsAgo);
        int24 _twap = int24((_tickCumulatives[1] - _tickCumulatives[0]) / int32(_twapDuration));

        uint256 _priceSqrt = (TickMath.getSqrtRatioAtTick(_twap) * 1e18) / 2 ** 96;
        // when the quote token was fliped.
        if (IUniswapV3Pool(_pool).token0() == WETH) {
            return 1e54 / _priceSqrt ** 2;
        }
        // uint256 _twapPrice = _priceSqrt ** 2 / 1e18;
        return _priceSqrt ** 2 / 1e18;
    }

    function __validateAggregator(address _primitive, address _pool, uint32 _duration) private view {
        require(_primitive != address(0), "primitive is null");
        require(_pool != address(0), "pool is null");
        require(_duration > 0, "duration is zero");

        require(
            IUniswapV3Pool(_pool).token0() == WETH || IUniswapV3Pool(_pool).token1() == WETH,
            "quote asset is not weth"
        );
    }
}
