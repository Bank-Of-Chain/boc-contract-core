// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "./ICustomPriceFeed.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface ICustomSEthCurveFi {
    function get_dy(int128 from, int128 to, uint256 _from_amount) external view returns (uint256);
}

contract CustomSEthPriceFeed is ICustomPriceFeed {
    address immutable ETH_USD_AGGREGATOR = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address immutable SUSD_USD_AGGREGATOR = 0xad35Bd71b9aFE6e4bDc266B345c198eaDEf9Ad94;
    address private constant W_ETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant FRX_ETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address private constant FRXETH_ETH_UNI_V3_POOL = 0x8a15b2Dc9c4f295DCEbB0E7887DD25980088fDCB;
    address private constant SETH_ETH_CURVE_POOL = 0xc5424B857f758E906013F3555Dad202e4bdB4567;

    function calcValueInUsd(uint256 _amount) external view override returns (uint256 _valueInUsd) {
        (, int256 _ethInUsdRate, , , ) = AggregatorV3Interface(ETH_USD_AGGREGATOR).latestRoundData();
        require(_ethInUsdRate > 0, "invalid price");

        uint256 _priceInETH = _sEthPriceInEth();
        return (_amount * _priceInETH * uint256(_ethInUsdRate)) / 1e26;// /1e8/getAssetUnit()
    }

    function calcValueInEth(uint256 _amount) external view override returns (uint256 _valueInEth) {
        uint256 _priceInETH = _sEthPriceInEth();
        return (_amount * _priceInETH) / 1e18;
    }

    function getAssetUnit() public view override returns (uint256 _unit) {
        return 10 ** 18;
    }

    function getRateAsset() external view override returns (IPrimitivePriceFeed.RateAsset _rateAsset) {
        return IPrimitivePriceFeed.RateAsset.ETH;
    }

    function _sEthPriceInEth() private view returns (uint256) {
        //curve price
        uint256 _priceInCurve = ICustomSEthCurveFi(SETH_ETH_CURVE_POOL).get_dy(1, 0, 1e18);
        (, int256 _sUSDOfUSD, , , ) = AggregatorV3Interface(SUSD_USD_AGGREGATOR).latestRoundData();
        require(_sUSDOfUSD > 0, "chain-link invalid");
        //chainlink price sETH/sUSD/USD/ETH
        uint256 _priceInChainLink = uint256(_sUSDOfUSD) * 1e10;
        uint256 _delta;
        uint256 _priceHigh;
        if (_priceInCurve > _priceInChainLink) {
            _delta = _priceInCurve - _priceInChainLink;
            _priceHigh = _priceInCurve;
        } else {
            _delta = _priceInChainLink - _priceInCurve;
            _priceHigh = _priceInChainLink;
        }
        require(_priceHigh * 8 > 1000 * _delta, "delta too much");
        // 0.9 price1 + 0.1 price2
        return (_priceInCurve * 9) / 10 + _priceInChainLink / 10;
    }
}
