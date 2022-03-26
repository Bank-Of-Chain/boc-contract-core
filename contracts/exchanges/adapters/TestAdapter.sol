// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import 'hardhat/console.sol';
import '../IExchangeAdapter.sol';
import '../../price-feeds/IValueInterpreter.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

contract TestAdapter is IExchangeAdapter {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address valueInterpreter;

    constructor(address _valueInterpreter) {
        valueInterpreter = _valueInterpreter;
    }

    function identifier() external pure override returns (string memory identifier_) {
        return 'testAdapter';
    }

    function swap(
        uint8 _method,
        bytes calldata _encodedCallArgs,
        IExchangeAdapter.SwapDescription calldata _sd
    ) external override returns (uint256) {
        console.log('[TestAdapter] swap:_sd.srcToken:%s, balanceOf:%s', _sd.srcToken, IERC20Upgradeable(_sd.srcToken).balanceOf(address(this)));
        console.log('[TestAdapter] swap:_sd.dstToken:%s, balanceOf:%s', _sd.dstToken, IERC20Upgradeable(_sd.dstToken).balanceOf(address(this)));
        // 估算一下大概能换多少目标币
        uint256 amount = IValueInterpreter(valueInterpreter).calcCanonicalAssetValue(_sd.srcToken, _sd.amount, _sd.dstToken);
        console.log('[TestAdapter] swap:_sd.amount=%s, amount=%s', _sd.amount, amount);
        // 模拟兑换环节，损失千分之三
        uint256 expectAmount = (amount * 1000) / 1000;
        IERC20Upgradeable(_sd.dstToken).safeTransfer(_sd.receiver, expectAmount);
        return expectAmount;
    }
}
