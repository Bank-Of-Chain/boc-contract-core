// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./IHarvester.sol";
import "./../access-control/AccessControlMixin.sol";
import "./../library/BocRoles.sol";
import "../vault/IVault.sol";
import "./../strategy/IStrategy.sol";

contract Harvester is IHarvester, AccessControlMixin, Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public profitReceiver;
    address public exchangeManager;
    /// rewards sell to token.
    address public sellTo;
    address public vaultAddress;

    function initialize(
        address _accessControlProxy,
        address _receiver,
        address _sellTo,
        address _vault
    ) external initializer {
        require(_receiver != address(0), "Must be a non-zero address");
        require(_vault != address(0), "Must be a non-zero address");
        require(_sellTo != address(0), "Must be a non-zero address");
        profitReceiver = _receiver;
        sellTo = _sellTo;
        vaultAddress = _vault;
        exchangeManager = IVault(_vault).exchangeManager();
        _initAccessControl(_accessControlProxy);
    }

    function setProfitReceiver(address _receiver) external override onlyRole(BocRoles.GOV_ROLE) {
        require(_receiver != address(0), "Must be a non-zero address");
        profitReceiver = _receiver;

        emit ReceiverChanged(profitReceiver);
    }

    function setSellTo(address _sellTo) external override isVaultManager {
        require(_sellTo != address(0), "Must be a non-zero address");
        sellTo = _sellTo;

        emit SellToChanged(sellTo);
    }

    /**
     * @dev Transfer token to governor. Intended for recovering tokens stuck in
     *      contract, i.e. mistaken sends.
     * @param _asset Address for the asset
     * @param _amount Amount of the asset to transfer
     */
    function transferToken(address _asset, uint256 _amount)
        external
        override
        onlyRole(BocRoles.GOV_ROLE)
    {
        IERC20Upgradeable(_asset).safeTransfer(IVault(vaultAddress).treasury(), _amount);
    }

    function collect(address[] calldata _strategies) external override isKeeper {
        for (uint256 i = 0; i < _strategies.length; i++) {
            address strategy = _strategies[i];
            IVault(vaultAddress).checkActiveStrategy(strategy);
            IStrategy(strategy).harvest();
        }
    }

    function exchangeAndSend(IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens)
        external
        override
        isKeeper
    {
        address sellToCopy = sellTo;
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            IExchangeAggregator.ExchangeToken memory exchangeToken = _exchangeTokens[i];
            require(exchangeToken.toToken == sellToCopy, "Rewards can only be sold as sellTo");
            _exchange(
                exchangeToken.fromToken,
                exchangeToken.toToken,
                exchangeToken.fromAmount,
                exchangeToken.exchangeParam
            );
        }
    }

    function _exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory exchangeParam
    ) internal returns (uint256 exchangeAmount) {
        IExchangeAdapter.SwapDescription memory swapDescription = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _fromToken,
            dstToken: _toToken,
            receiver: profitReceiver
        });
        IERC20Upgradeable(_fromToken).safeApprove(exchangeManager, _amount);
        exchangeAmount = IExchangeAggregator(exchangeManager).swap(
            exchangeParam.platform,
            exchangeParam.method,
            exchangeParam.encodeExchangeArgs,
            swapDescription
        );
        emit Exchange(exchangeParam.platform, _fromToken, _amount, _toToken, exchangeAmount);
    }
}
