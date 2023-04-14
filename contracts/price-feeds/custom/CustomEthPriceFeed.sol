// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./ICustomPriceFeed.sol";


contract CustomEthPriceFeed is ICustomPriceFeed {
    address immutable ETH_USD_AGGREGATOR = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    /// @notice query Eth-Usd priceFeed
    function calcValueInUsd(uint256 _amount) external view override returns (uint256 _valueInUsd) {
        (, int256 _ethInUsdRate, , , ) = AggregatorV3Interface(ETH_USD_AGGREGATOR).latestRoundData();

        return uint(_ethInUsdRate) * _amount * 1e10 / getAssetUnit(); // * 1e18 / 1e8
    }

    /// @notice 1Eth = 1Eth
    function calcValueInEth(uint256 _amount) external pure override returns (uint256 _valueInEth) {
        return _amount;
    }

    function getAssetUnit() public pure override returns (uint256 _unit) {
        return 10 ** 18;
    }

    function getRateAsset() external view override returns (IPrimitivePriceFeed.RateAsset _rateAsset) {
        return IPrimitivePriceFeed.RateAsset.ETH;
    }
}
