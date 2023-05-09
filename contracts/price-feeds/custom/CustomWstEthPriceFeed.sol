// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "./ICustomPriceFeed.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IWstETH {
    function stEthPerToken() external view returns (uint256);

    function tokensPerStEth() external view returns (uint256);

    function decimals() external view returns (uint256);
}

contract CustomWstEthPriceFeed is ICustomPriceFeed {
    address immutable ETH_USD_AGGREGATOR = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address immutable WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address immutable STETH_USD_PRICEFEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address immutable STETH_ETH_PRICEFEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    function calcValueInUsd(uint256 _amount) external view override returns (uint256 _valueInUsd) {

        (, int256 _ethInUsdRate, , , ) = AggregatorV3Interface(ETH_USD_AGGREGATOR).latestRoundData();

        return uint(_ethInUsdRate) * _amount * 1e10 / getAssetUnit(); // * 1e18 / 1e8
    }

    function calcValueInEth(uint256 _amount) external view override returns (uint256 _valueInEth) {
        (, int256 _stEthInEthRate, , , ) = AggregatorV3Interface(STETH_ETH_PRICEFEED).latestRoundData();
        uint256 _stEthPerToken = IWstETH(WSTETH).stEthPerToken();

        _valueInEth = (_amount * _stEthPerToken * uint256(_stEthInEthRate)) / 1e18 / getAssetUnit();
    }

    function getAssetUnit() public view override returns (uint256 _unit) {
        return 10 ** IWstETH(WSTETH).decimals();
    }

    function getRateAsset() external pure override returns (IPrimitivePriceFeed.RateAsset _rateAsset) {
        return IPrimitivePriceFeed.RateAsset.ETH;
    }
}
