// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IValueInterpreter {

    /*
    * 资产数量换算
    * srcToken: 源token地址
    * srcNum: 源token数量
    * destToken: 目标token地址
    */
    function calcCanonicalAssetValue(
        address srcToken,
        uint256 srcNum,
        address destToken
    ) external view returns (uint256);

    /*
    * 资产数量换算(批量接口)
    */
    function calcCanonicalAssetsTotalValue(
        address[] calldata,
        uint256[] calldata,
        address
    ) external view returns (uint256);

    /*
    * 资产的usd价值
    * _baseAsset: 源token地址
    * _amount: 源token数量
    * @return usd(1e18)
    */
    function calcCanonicalAssetValueInUsd(
        address _baseAsset,
        uint256 _amount
    ) external view returns (uint256);

    /*
    * baseUnit数量资产的usd价值
    * _baseAsset: 源token地址
    * @return usd(1e18)
    */
    function price(address _baseAsset) external view returns (uint256);
}
