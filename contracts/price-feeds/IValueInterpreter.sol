// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IValueInterpreter {

    /*
    * Calculate the conversion of a specified number of assets
    * srcToken: Source token address
    * srcNum: Number of source token
    * destToken: Target token address
    */
    function calcCanonicalAssetValue(
        address srcToken,
        uint256 srcNum,
        address destToken
    ) external view returns (uint256);

    /*
    * Calculate the conversion of a specified number of assets(batch)
    */
    function calcCanonicalAssetsTotalValue(
        address[] calldata,
        uint256[] calldata,
        address
    ) external view returns (uint256);

    /*
    * Calculate the usd value of a specified number of assets
    * _baseAsset: Source token address
    * _amount: Number of source token
    * @return usd(1e18)
    */
    function calcCanonicalAssetValueInUsd(
        address _baseAsset,
        uint256 _amount
    ) external view returns (uint256);

    /*
    * Calculate the usd value of baseUnit volume assets
    * _baseAsset: asset token address
    * @return usd(1e18)
    */
    function price(address _baseAsset) external view returns (uint256);
}
