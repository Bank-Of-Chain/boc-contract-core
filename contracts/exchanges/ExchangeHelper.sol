import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../library/RevertReasonParser.sol";
import "../library/NativeToken.sol";

import "../access-control/AccessControlMixin.sol";

pragma solidity 0.8.17;

abstract contract ExchangeHelper is AccessControlMixin {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The 1inch router contract address
    address public oneInchRouter;

    /// @notice The paraswap router contract address
    address public paraRouter;
    /// @notice The paraswap transfer proxy contract address
    address public paraTransferProxy;

    /// @param  _platform The platform used for the exchange
    /// @param _srcAsset The address of asset exchange from 
    /// @param _srcAmount The amount of asset exchange from 
    /// @param _distAsset The address of asset exchange to 
    /// @param _distAmount The amount of asset exchange to 
    event Exchange(
        address _platform,
        address _srcAsset,
        uint256 _srcAmount,
        address _distAsset,
        uint256 _distAmount
    );

    function exchange(
        address _fromToken,
        address _toToken,
        uint256 _fromAmount,
        bytes calldata _calldata,
        uint16 _platformType
    ) public payable returns (
            bool _success, 
            uint256 _returnAmount
    ) {
        address platform;
        if(_platformType == 0) {
            // use 1inch platform
            (_success,_returnAmount) = exchangeOn1Inch(oneInchRouter, _fromToken, _toToken, _fromAmount, _calldata);
            platform = oneInchRouter;
        } else if (_platformType == 1) {
            // use paraswap platform
            (_success,_returnAmount) = exchangeOnPara(paraRouter, paraTransferProxy,_fromToken, _toToken, _fromAmount, _calldata);
            platform = paraRouter;
        }
        emit Exchange(platform, _fromToken, _fromAmount, _toToken, _returnAmount);
    }

    function set1inchRouter(address _newRouter) external isKeeperOrVaultOrGovOrDelegate{
        require(_newRouter != address(0),"NZ");//The new router cannot be 0x00
        oneInchRouter = _newRouter;
    }

    function setParaRouter(address _newRouter) external isKeeperOrVaultOrGovOrDelegate{
        require(_newRouter != address(0),"NZ");//The new router cannot be 0x00
        paraRouter = _newRouter;
    }

    function setParaTransferProxy(address _newTransferProxy) external isKeeperOrVaultOrGovOrDelegate{
        require(_newTransferProxy != address(0),"NZ");//The new transfer proxy cannot be 0x00
        paraTransferProxy = _newTransferProxy;
    }

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