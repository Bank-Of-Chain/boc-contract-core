// ExchangeLib.sol
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./RevertReasonParser.sol";
import "./NativeToken.sol";

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

        uint256 beforeBalOfToToken = _balanceOfToken(_toToken, address(this));
        if (_fromToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            (_success, _result) = payable(_oneInchRouter).call{value: _fromAmount}(_calldata);
        } else {
            IERC20Upgradeable(_fromToken).safeApprove(_oneInchRouter, 0);
            IERC20Upgradeable(_fromToken).safeApprove(_oneInchRouter, _fromAmount);
            (_success, _result) = _oneInchRouter.call(_calldata);

        }
        uint256 afterBalOfToToken = _balanceOfToken(_toToken, address(this));

        if (!_success) {
            revert(RevertReasonParser.parse(_result, "1inch V4 swap failed: "));
        } else {
            _returnAmount = afterBalOfToToken - beforeBalOfToToken;
        }

        return (_success, _returnAmount);
    }

    function exchangeOnPara(
        address _paraRouter,
        address _paraTransferProxy,
        address _fromToken,
        address _toToken,
        uint256 _fromAmount,
        bytes calldata _calldata
    ) internal returns (
            bool _success, 
            uint256 _returnAmount
    ) {
        bytes memory _result;

        uint256 beforeBalOfToToken = _balanceOfToken(_toToken, address(this));
        if (_fromToken == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            (_success, _result) = payable(_paraRouter).call{value: _fromAmount}(_calldata);
        } else {
            IERC20Upgradeable(_fromToken).safeApprove(_paraTransferProxy, 0);
            IERC20Upgradeable(_fromToken).safeApprove(_paraTransferProxy, _fromAmount);
            (_success, _result) = _paraRouter.call(_calldata);
        }
        uint256 afterBalOfToToken = _balanceOfToken(_toToken, address(this));

        if (!_success) {
            revert(RevertReasonParser.parse(_result, "paraswap callBytes failed: "));
        } 

        _returnAmount = afterBalOfToToken - beforeBalOfToToken;

        return (_success, _returnAmount);
    }

    function _balanceOfToken(address _trackedAsset, address _owner) internal view returns (uint256) {
        uint256 _balance;
        if (_trackedAsset == NativeToken.NATIVE_TOKEN) {
            _balance = _owner.balance;
        } else {
            _balance = IERC20Upgradeable(_trackedAsset).balanceOf(_owner);
        }
        return _balance;
    }
}
