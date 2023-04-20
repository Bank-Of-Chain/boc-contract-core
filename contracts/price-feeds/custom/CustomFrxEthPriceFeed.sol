// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "./ICustomPriceFeed.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

interface ICustomFrxEthCurveFi {
    function price_oracle() external view returns (uint256);
}

contract CustomFrxEthPriceFeed is ICustomPriceFeed {
    address immutable ETH_USD_AGGREGATOR = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private constant W_ETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant FRX_ETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address private constant FRXETH_ETH_UNI_V3_POOL = 0x8a15b2Dc9c4f295DCEbB0E7887DD25980088fDCB;
    address private constant FRXETH_ETH_CURVE_POOL = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;

    function calcValueInUsd(uint256 _amount) external view override returns (uint256 _valueInUsd) {
        (, int256 _ethInUsdRate, , , ) = AggregatorV3Interface(ETH_USD_AGGREGATOR).latestRoundData();
        require(_ethInUsdRate > 0, "invalid price");

        uint256 _priceInETH = _frxEthPriceInEth();
        return (_amount * _priceInETH * uint256(_ethInUsdRate)) / 1e26; // /1e8/getAssetUnit()
    }

    function calcValueInEth(uint256 _amount) external view override returns (uint256 _valueInEth) {
        uint256 _priceInETH = _frxEthPriceInEth();
        return (_amount * _priceInETH) / 1e18;
    }

    function getAssetUnit() public view override returns (uint256 _unit) {
        return 10 ** 18;
    }

    function getRateAsset() external view override returns (IPrimitivePriceFeed.RateAsset _rateAsset) {
        return IPrimitivePriceFeed.RateAsset.ETH;
    }

    function _quote(
        uint128 _baseAmount,
        address _baseToken,
        address _quoteToken,
        address _pool,
        uint32 _period
    ) internal view returns (uint256 _quoteAmount) {
        require(_period > 0);
        int24 _weightedTick = OracleLibrary.consult(_pool, _period);
        return OracleLibrary.getQuoteAtTick(_weightedTick, _baseAmount, _baseToken, _quoteToken);
    }

    function _frxEthPriceInEth() private view returns (uint256) {
        uint256 _priceInCurve = ICustomFrxEthCurveFi(FRXETH_ETH_CURVE_POOL).price_oracle();
        uint256 _priceInUniV3 = _quote(1e18, FRX_ETH, W_ETH, FRXETH_ETH_UNI_V3_POOL, 600);

        uint256 _delta;
        uint256 _priceHigh;
        if (_priceInCurve > _priceInUniV3) {
            _delta = _priceInCurve - _priceInUniV3;
            _priceHigh = _priceInCurve;
        } else {
            _delta = _priceInUniV3 - _priceInCurve;
            _priceHigh = _priceInUniV3;
        }
        require(_priceHigh * 2 > 1000 * _delta, "delta too much");
        // 0.9 price1 + 0.1 price2
        return (_priceInCurve * 9) / 10 + _priceInUniV3 / 10;
    }
}
