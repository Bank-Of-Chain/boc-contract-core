// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "./ICustomPriceFeed.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";


interface ICustomFrxEthCurveFi {
    function price_oracle() external view returns (uint256);
}

contract CustomFrxEthPriceFeed is ICustomPriceFeed {
    address immutable ETH_USD_AGGREGATOR = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant FRX_ETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address private constant FRXETH_ETH_UNI_V3_POOL = 0x8a15b2Dc9c4f295DCEbB0E7887DD25980088fDCB;
    address private constant FRXETH_ETH_CURVE_POOL = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;

    function calcValueInUsd(uint256 _amount) external view override returns (uint256 _valueInUsd) {

        (, int256 _ethInUsdRate, , , ) = AggregatorV3Interface(ETH_USD_AGGREGATOR).latestRoundData();
        require(_ethInUsdRate>0,"invalid price");

        uint256 _priceInETH = _frxEthPriceInEth();
        return (_amount * _priceInETH * uint256(_ethInUsdRate)) / 1e8;
    }

    function calcValueInEth(uint256 _amount) external view override returns (uint256 _valueInEth) {
        uint256 _priceInETH = _frxEthPriceInEth();
        return (_amount * _priceInETH) / 1e18;
    }

    function getAssetUnit() public view override returns (uint256 _unit) {
        return 10 ** 18;
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
        uint256 price1 = ICustomFrxEthCurveFi(FRXETH_ETH_CURVE_POOL).price_oracle();
        uint256 price2 = _quote(1e18, FRX_ETH, wETH, FRXETH_ETH_UNI_V3_POOL, 600);

        uint256 delta;
        uint256 priceHigh;
        if (price1 > price2) {
            delta = price1 - price2;
            priceHigh = price1;
        } else {
            delta = price2 - price1;
            priceHigh = price2;
        }
        require(priceHigh * 2 > 1000 * delta, "delta too much");
        // 0.9 price1 + 0.1 price2
        return (price1 * 9) / 10 + price2 / 10;
    }
}
