// ExchangeLib.sol
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./RevertReasonParser.sol";

library ExchangeLib {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function exchangeOn1Inch(
        address _oneInchRouter,
        address _fromToken,
        address _toToken,
        uint256 _fromAmount,
        bytes calldata _calldata
    ) internal returns (
            bool _success, 
            uint256 _returnAmount
    ) {
        bytes memory _result;
        uint256 beforeBalOfToToken;
        uint256 afterBalOfToToken;
        if (_fromToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            beforeBalOfToToken = IERC20Upgradeable(_toToken).balanceOf(address(this));
            (_success, _result) = payable(_oneInchRouter).call{value: _fromAmount}(_calldata);
            afterBalOfToToken = IERC20Upgradeable(_toToken).balanceOf(address(this));
        } else {
            IERC20Upgradeable(_fromToken).safeApprove(_oneInchRouter, 0);
            IERC20Upgradeable(_fromToken).safeApprove(_oneInchRouter, _fromAmount);

            if(_toToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                beforeBalOfToToken = address(this).balance;
                (_success, _result) = _oneInchRouter.call(_calldata);
                afterBalOfToToken = address(this).balance;
            }else {
                beforeBalOfToToken = IERC20Upgradeable(_toToken).balanceOf(address(this));
                (_success, _result) = _oneInchRouter.call(_calldata);
                afterBalOfToToken = IERC20Upgradeable(_toToken).balanceOf(address(this));
            }
        }

        if (!_success) {
            revert(RevertReasonParser.parse(_result, "1inch V4 swap failed: "));
        } else {
            _returnAmount = afterBalOfToToken - beforeBalOfToToken;
        }

        return (_success, _returnAmount);
    }
}
