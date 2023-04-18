// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../library/RevertReasonParser.sol";
import "../library/NativeToken.sol";
import "../access-control/AccessControlMixin.sol";

abstract contract ExchangeHelper is Initializable, AccessControlMixin {
    using SafeERC20Upgradeable for IERC20Upgradeable;

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

    function __InitializeRouters() internal onlyInitializing {
        oneInchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;
        paraRouter = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;
        paraTransferProxy = 0x216B4B4Ba9F3e719726886d34a177484278Bfcae;
    }

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

    function exchangeOn1Inch(
        address _fromToken,
        address _toToken,
        uint256 _fromAmount,
        bytes memory _calldata
    ) internal returns (uint256 _returnAmount) {
        uint256 _beforeBalOfToToken = _balanceOfToken(_toToken, address(this));
        address _oneInchRouter = oneInchRouter;
        bool _success;
        bytes memory _result;
        if (_fromToken == NativeToken.NATIVE_TOKEN) {
            (_success, _result) = payable(_oneInchRouter).call{value: _fromAmount}(_calldata);
        } else {
            IERC20Upgradeable(_fromToken).safeApprove(_oneInchRouter, 0);
            IERC20Upgradeable(_fromToken).safeApprove(_oneInchRouter, _fromAmount);
            (_success, _result) = _oneInchRouter.call(_calldata);
        }

        if (!_success) {
            revert(RevertReasonParser.parse(_result, "1inch swap failed: "));
        }

        uint256 _afterBalOfToToken = _balanceOfToken(_toToken, address(this));
        _returnAmount = _afterBalOfToToken - _beforeBalOfToToken;
    }

    function exchangeOnPara(
        address _fromToken,
        address _toToken,
        uint256 _fromAmount,
        bytes memory _calldata
    ) internal returns (uint256 _returnAmount) {
        uint256 _beforeBalOfToToken = _balanceOfToken(_toToken, address(this));
        address _paraRouter = paraRouter;
        address _paraTransferProxy = paraTransferProxy;
        bool _success;
        bytes memory _result;
        if (_fromToken == NativeToken.NATIVE_TOKEN) {
            (_success, _result) = payable(_paraRouter).call{value: _fromAmount}(_calldata);
        } else {
            IERC20Upgradeable(_fromToken).safeApprove(_paraTransferProxy, 0);
            IERC20Upgradeable(_fromToken).safeApprove(_paraTransferProxy, _fromAmount);
            (_success, _result) = _paraRouter.call(_calldata);
        }

        if (!_success) {
            revert(RevertReasonParser.parse(_result, "paraswap callBytes failed: "));
        }

        uint256 _afterBalOfToToken = _balanceOfToken(_toToken, address(this));
        _returnAmount = _afterBalOfToToken - _beforeBalOfToToken;
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
