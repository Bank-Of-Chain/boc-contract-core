// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./../access-control/AccessControlMixin.sol";
import "./../library/BocRoles.sol";
import "./../strategy/IStrategy.sol";
import "../exchanges/IExchangeAggregator.sol";

contract Harvester is AccessControlMixin, Initializable {
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
    ) external initializer {
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
        onlyRole(BocRoles.GOV_ROLE)
    {
        require(_receiver != address(0), "Must be a non-zero address");
        profitReceiver = _receiver;

        emit ReceiverChanged(profitReceiver);
    }

    //TODO 是否可以直接链外控制兑换成什么，但是兑换的目标币需要是vault里支持的稳定币
    function setSellTo(address _sellTo)
        external
        onlyRole(BocRoles.KEEPER_ROLE)
    {
        require(_sellTo != address(0), "Must be a non-zero address");
        sellTo = _sellTo;

        emit SellToChanged(sellTo);
    }

    // TODO 如果strategy是别人的地址，虚拟了一个harvest方法。
    // 支持collectAndSwapAndSend
    function collect(address[] calldata _strategies) external {
        for (uint8 i = 0; i < _strategies.length; i++) {
            address strategyAdd = _strategies[i];
            IStrategy(strategyAdd).harvest();
        }
    }

    // function sendAssetsToReceiver(
    //     address[] memory _assets,
    //     uint256[] memory _amounts
    // ) external onlyRole(BocRoles.KEEPER_ROLE) {
    //     for (uint8 i = 0; i < _assets.length; i++) {
    //         address token = _assets[i];
    //         uint256 amount = _amounts[i];
    //         IERC20Upgradeable(token).safeTransfer(profitReceiver, amount);
    //     }
    // }

    function exchangeAndSend(
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) external onlyRole(BocRoles.KEEPER_ROLE) {
        for (uint8 i = 0; i < _exchangeTokens.length; i++) {
            IExchangeAggregator.ExchangeToken
                memory exchangeToken = _exchangeTokens[i];
            require(
                exchangeToken.toToken == sellTo,
                "Rewards can only be sold as sellTo"
            );
            _exchange(
                exchangeToken.fromToken,
                exchangeToken.toToken,
                exchangeToken.fromAmount,
                exchangeToken.exchangeParam
            );
        }

        uint256 sellToBalance = IERC20Upgradeable(sellTo).balanceOf(
            address(this)
        );
        if (sellToBalance > 0) {
            IERC20Upgradeable(sellTo).safeTransfer(
                profitReceiver,
                sellToBalance
            );
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
        emit Exchange(
            exchangeParam.platform,
            _fromToken,
            _amount,
            _toToken,
            exchangeAmount
        );
    }
}
