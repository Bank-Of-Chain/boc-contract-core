// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../library/RevertReasonParser.sol";
import "../library/NativeToken.sol";
import "../access-control/AccessControlMixin.sol";
import "../util/AssetHelpers.sol";

abstract contract ExchangeHelper is AssetHelpers, Initializable, AccessControlMixin {
    enum ExchangePlatform {
        ONE_INCH,
        PARA_SWAP
    }

    struct ExchangeParams {
        ExchangePlatform platform;
        address fromToken;
        address toToken;
        uint256 fromAmount;
        bytes txData;
    }

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
        ExchangePlatform _platform,
        address _srcAsset,
        uint256 _srcAmount,
        address _distAsset,
        uint256 _distAmount
    );

    function __InitializeRouters() internal {
        oneInchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;
        paraRouter = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;
        paraTransferProxy = 0x216B4B4Ba9F3e719726886d34a177484278Bfcae;
    }

    /// @dev Exchange tokens using a third party exchange platform.  
    /// Current support: 1Inch and ParaSwap. 
    /// @param _fromToken address of token being exchanged
    /// @param _toToken address of token being received
    /// @param _fromAmount amount of token being exchanged
    /// @param _calldata calldata to exchange the tokens
    /// @param _platform exchange platform for the exchange
    /// @return _returnAmount the amount of token received
    function _exchange(
        address _fromToken,
        address _toToken,
        uint256 _fromAmount,
        bytes memory _calldata,
        ExchangePlatform _platform
    ) internal returns (uint256 _returnAmount) {
        if (_platform == ExchangePlatform.ONE_INCH) {
            // use 1inch platform
            _returnAmount = exchangeOn1Inch(_fromToken, _toToken, _fromAmount, _calldata);
        } else if (_platform == ExchangePlatform.PARA_SWAP) {
            // use paraswap platform
            _returnAmount = exchangeOnPara(_fromToken, _toToken, _fromAmount, _calldata);
        } else {
            revert("Invalid platform");
        }
        emit Exchange(_platform, _fromToken, _fromAmount, _toToken, _returnAmount);
    }

    function set1inchRouter(address _newRouter) external isKeeperOrVaultOrGovOrDelegate {
        require(_newRouter != address(0), "NZ"); //The new router cannot be 0x00
        oneInchRouter = _newRouter;
    }

    function setParaRouter(address _newRouter) external isKeeperOrVaultOrGovOrDelegate {
        require(_newRouter != address(0), "NZ"); //The new router cannot be 0x00
        paraRouter = _newRouter;
    }

    function setParaTransferProxy(address _newTransferProxy) external isKeeperOrVaultOrGovOrDelegate {
        require(_newTransferProxy != address(0), "NZ"); //The new transfer proxy cannot be 0x00
        paraTransferProxy = _newTransferProxy;
    }

    /// This internal function conducts a token swap on the 1Inch exchange and returns the amount of the '_toToken' exchanged.
    /// @param _fromToken The address of the token to be exchanged.
    /// @param _toToken The address of the token to be received in the swap.
    /// @param _fromAmount The amount of the '_fromToken' to be exchanged.
    /// @param _calldata The calldata for the 1Inch swap.
    /// @return _returnAmount The amount of the '_toToken' exchanged in the swap.
    function exchangeOn1Inch(
        address _fromToken,
        address _toToken,
        uint256 _fromAmount,
        bytes memory _calldata
    ) internal returns (uint256 _returnAmount) {
        uint256 _beforeBalOfToToken = __balanceOfToken(_toToken, address(this));
        address _oneInchRouter = oneInchRouter;
        bool _success;
        bytes memory _result;
        if (__isNativeToken(_fromToken)) {
            // slither-disable-next-line low-level-calls
            (_success, _result) = payable(_oneInchRouter).call{value: _fromAmount}(_calldata);
        } else {
            __approveAssetMaxAsNeeded(_fromToken, _oneInchRouter, _fromAmount);
            // slither-disable-next-line low-level-calls
            (_success, _result) = _oneInchRouter.call(_calldata);
        }

        if (!_success) {
            revert(RevertReasonParser.parse(_result, "1inch swap failed: "));
        }

        uint256 _afterBalOfToToken = __balanceOfToken(_toToken, address(this));
        _returnAmount = _afterBalOfToToken - _beforeBalOfToToken;
    }

    /// This function is used to exchange tokens on Paraswap, transferring a given amount of _fromToken to receive an equivalent amount of _toToken.
    /// @param _fromToken The address of the token to be exchanged.
    /// @param _toToken The address of the token to be received in the swap.
    /// @param _fromAmount The amount of the '_fromToken' to be exchanged.
    /// @param _calldata The calldata for the paraswap.
    /// @return _returnAmount The amount of the '_toToken' exchanged in the swap.
    function exchangeOnPara(
        address _fromToken,
        address _toToken,
        uint256 _fromAmount,
        bytes memory _calldata
    ) internal returns (uint256 _returnAmount) {
        uint256 _beforeBalOfToToken = __balanceOfToken(_toToken, address(this));
        address _paraRouter = paraRouter;
        address _paraTransferProxy = paraTransferProxy;
        bool _success;
        bytes memory _result;
        if (__isNativeToken(_fromToken)) {
            // slither-disable-next-line low-level-calls
            (_success, _result) = payable(_paraRouter).call{value: _fromAmount}(_calldata);
        } else {
            __approveAssetMaxAsNeeded(_fromToken, _paraTransferProxy, _fromAmount);
            // slither-disable-next-line low-level-calls
            (_success, _result) = _paraRouter.call(_calldata);
        }

        if (!_success) {
            revert(RevertReasonParser.parse(_result, "paraswap callBytes failed: "));
        }

        uint256 _afterBalOfToToken = __balanceOfToken(_toToken, address(this));
        _returnAmount = _afterBalOfToToken - _beforeBalOfToToken;
    }
}
