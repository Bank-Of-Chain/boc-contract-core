// SPDX-License-Identifier: MIT

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
}
