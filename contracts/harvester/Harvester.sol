// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./../access-control/AccessControlMixin.sol";
import "./../library/BocRoles.sol";
import "./../strategy/IStrategy.sol";
import "./IHarvester.sol";

contract Harvester is IHarvester, AccessControlMixin, Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public profitReceiver;
    address public exchangeManager;
    /// rewards sell to token.
    address public sellTo;

    function initialize(
        address _accessControlProxy,
        address _receiver,
        address _sellTo,
        address _exchangeManager
    ) public initializer {
        require(_receiver != address(0), "Must be a non-zero address");
        require(_sellTo != address(0), "Must be a non-zero address");
        require(_exchangeManager != address(0), "Must be a non-zero address");
        profitReceiver = _receiver;
        sellTo = _sellTo;
        exchangeManager = _exchangeManager;
        _initAccessControl(_accessControlProxy);
    }

    function setProfitReceiver(address _receiver)
        external
        override
        onlyRole(BocRoles.GOV_ROLE)
    {
        require(_receiver != address(0), "Must be a non-zero address");
        profitReceiver = _receiver;

        emit ReceiverChanged(profitReceiver);
    }

    function setSellTo(address _sellTo)
        external
        override
        onlyRole(BocRoles.KEEPER_ROLE)
    {
        require(_sellTo != address(0), "Must be a non-zero address");
        sellTo = _sellTo;

        emit SellToChanged(sellTo);
    }

    function collect(address[] calldata _strategies) external override {
        for (uint8 i = 0; i < _strategies.length; i++) {
            address strategyAdd = _strategies[i];
            IStrategy(strategyAdd).harvest();
        }
    }

    // function sendAssetsToReceiver(
    //     address[] memory _assets,
    //     uint256[] memory _amounts
    // ) external override onlyRole(BocRoles.KEEPER_ROLE) {
    //     for (uint8 i = 0; i < _assets.length; i++) {
    //         address token = _assets[i];
    //         uint256 amount = _amounts[i];
    //         IERC20Upgradeable(token).safeTransfer(profitReceiver, amount);
    //     }
    // }

    function exchangeAndSend(
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) external override onlyRole(BocRoles.KEEPER_ROLE) {
        for (uint8 i = 0; i < _exchangeTokens.length; i++) {
            IExchangeAggregator.ExchangeToken
                memory exchangeToken = _exchangeTokens[i];
            require(exchangeToken.toToken == sellTo,"Rewards can only be sold as sellTo");
            _exchange(
                exchangeToken.fromToken,
                exchangeToken.toToken,
                exchangeToken.fromAmount,
                exchangeToken.exchangeParam
            );
        }

        uint sellToBalance = IERC20Upgradeable(sellTo).balanceOf(address(this));
        if (sellToBalance > 0){
            IERC20Upgradeable(sellTo).safeTransfer(profitReceiver,sellToBalance);
        }
    }

    function _exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory exchangeParam
    ) internal returns (uint256 exchangeAmount) {

        IExchangeAdapter.SwapDescription
            memory swapDescription = IExchangeAdapter.SwapDescription({
                amount: _amount,
                srcToken: _fromToken,
                dstToken: _toToken,
                receiver: address(this)
            });
        IERC20Upgradeable(_fromToken).safeApprove(exchangeManager, _amount);
        exchangeAmount = IExchangeAggregator(exchangeManager).swap(
            exchangeParam.platform,
            exchangeParam.method,
            exchangeParam.encodeExchangeArgs,
            swapDescription
        );
        // uint256 oracleExpectedAmount = IValueInterpreter(valueInterpreter)
        //     .calcCanonicalAssetValue(_fromToken, _amount, _toToken);
        // require(
        //     exchangeAmount >=
        //         (oracleExpectedAmount *
        //             (MAX_BPS -
        //                 exchangeParam.slippage -
        //                 exchangeParam.oracleAdditionalSlippage)) /
        //             MAX_BPS,
        //     "OL"
        // );
        emit Exchange(_fromToken, _amount, _toToken, exchangeAmount);
    }
}
