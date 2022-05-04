// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import 'hardhat/console.sol';
import '../../external/oneinch/IOneInchV4.sol';
import '../IExchangeAdapter.sol';
import '../utils/ExchangeHelpers.sol';

import '@openzeppelin/contracts~v3/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts~v3/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts~v3/math/SafeMath.sol';
import '../../library/RevertReasonParser.sol';

contract EthOneInchV4Adapter is IExchangeAdapter, ExchangeHelpers {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    event Response(bool success, bytes data);
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address private immutable AGGREGATION_ROUTER_V4 = address(0x1111111254fb6c44bAC0beD2854e76F90643097d);

    /// @notice Provides a constant string identifier for an adapter
    /// @return identifier_ An identifier string
    function identifier() external pure override returns (string memory identifier_) {
        return 'oneInchV4';
    }

    function swap(uint8, bytes calldata _data, SwapDescription calldata _sd) external payable override returns (uint256){
        uint256 toTokenBefore;
        if(_sd.dstToken == ETH){
            toTokenBefore = address(this).balance;
        }else{
            toTokenBefore = IERC20(_sd.dstToken).balanceOf(address(this));
            (bool success, bytes memory result) = payable(AGGREGATION_ROUTER_V4).call{value: _sd.amount}(_data);
            emit Response(success, result);
            if (!success) {
                revert(RevertReasonParser.parse(result, '1inch V4 swap failed: '));
            }
        }
        if(_sd.srcToken != ETH){
            IERC20(_sd.srcToken).safeApprove(AGGREGATION_ROUTER_V4, 0);
            IERC20(_sd.srcToken).safeApprove(AGGREGATION_ROUTER_V4, _sd.amount);
            (bool success, bytes memory result) = AGGREGATION_ROUTER_V4.call(_data);
            emit Response(success, result);
            if (!success) {
                revert(RevertReasonParser.parse(result, '1inch V4 swap failed: '));
            }
        }

        uint256 exchangeAmount;
        if(_sd.dstToken == ETH){
            exchangeAmount = address(this).balance - toTokenBefore;
            payable(_sd.receiver).transfer(exchangeAmount);
        }else{
            exchangeAmount = IERC20(_sd.dstToken).balanceOf(address(this)) - toTokenBefore;
            IERC20(_sd.dstToken).safeTransfer(_sd.receiver, exchangeAmount);
        }
        return exchangeAmount;
    }

    receive() external payable {
    }
}
