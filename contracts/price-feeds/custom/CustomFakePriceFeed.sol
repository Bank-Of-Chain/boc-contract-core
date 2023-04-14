// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "./ICustomPriceFeed.sol";


contract CustomFakePriceFeed is ICustomPriceFeed {
    /// @notice fake price : FakeToken = 120USD.
    function calcValueInUsd(uint256 _amount) external pure override returns (uint256 _valueInUsd) {
        _valueInUsd = _amount * 120;
    }

    /// @notice fake price : FakeToken = 120USD,ETH = 1500USD.
    function calcValueInEth(uint256 _amount) external pure override returns (uint256 _valueInEth) {
        _valueInEth = _amount * 120 / 1500;
    }

    function getAssetUnit() public pure override returns (uint256 _unit) {
        return 10 ** 18;
    }

    function getRateAsset() external view override returns (IPrimitivePriceFeed.RateAsset _rateAsset) {
        return IPrimitivePriceFeed.RateAsset.ETH;
    }
}
