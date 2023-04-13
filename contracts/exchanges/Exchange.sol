import "../library/ExchangeLib.sol";
import "../access-control/AccessControlMixin.sol";

pragma solidity 0.8.17;

abstract contract Exchange is AccessControlMixin {
    using ExchangeLib for address;

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
            (_success,_returnAmount) = oneInchRouter.exchangeOn1Inch(_fromToken, _toToken, _fromAmount, _calldata);
            platform = oneInchRouter;
        } else if (_platformType == 1) {
            // use paraswap platform
            (_success,_returnAmount) = paraRouter.exchangeOnPara(paraTransferProxy,_fromToken, _toToken, _fromAmount, _calldata);
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
    
}