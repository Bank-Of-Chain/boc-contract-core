// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./../access-control/AccessControlMixin.sol";
import "./../library/BocRoles.sol";
import "../vault/IVault.sol";
import "./../strategy/IStrategy.sol";
import "../exchanges/IExchangeAggregator.sol";

contract Harvester is AccessControlMixin, Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event Exchange(
        address _platform,
        address fromToken,
        uint256 fromAmount,
        address toToken,
        uint256 exchangeAmount
    );
    event ReceiverChanged(address _receiver);
    event SellToChanged(address _sellTo);

    address public profitReceiver;
    address public exchangeManager;
    /// rewards sell to token.
    address public sellTo;
    IVault public vault;

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
        vault = IVault(_vault);
        exchangeManager = vault.exchangeManager();
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

    function setSellTo(address _sellTo) external isVaultManager {
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
        onlyRole(BocRoles.GOV_ROLE)
    {
        IERC20Upgradeable(_asset).safeTransfer(vault.treasury(), _amount);
    }

    function collect(address[] calldata _strategies) external isKeeper {
        for (uint256 i = 0; i < _strategies.length; i++) {
            address strategy = _strategies[i];
            vault.checkActiveStrategy(strategy);
            IStrategy(strategy).harvest();
        }
    }

    function collectAndSwapAndSend(
        address[] calldata _strategies,
        IExchangeAggregator.ExchangeToken[] memory _exchangeTokens
    ) external isKeeper {
        address sellToCopy = sellTo;
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            require(
                _exchangeTokens[i].toToken == sellToCopy,
                "Rewards can only be sold as sellTo"
            );
            _exchangeTokens[i].fromAmount = 0;
        }
        for (uint256 i = 0; i < _strategies.length; i++) {
            address strategy = _strategies[i];
            vault.checkActiveStrategy(strategy);
            (
                address[] memory _rewardsTokens,
                uint256[] memory _claimAmounts
            ) = IStrategy(strategy).harvest();
            for (uint256 j = 0; j < _rewardsTokens.length; j++) {
                if (_claimAmounts[j] > 0) {
                    for (uint256 k = 0; k < _exchangeTokens.length; k++) {
                        if (_exchangeTokens[k].fromToken == _rewardsTokens[j]) {
                            _exchangeTokens[k].fromAmount += _claimAmounts[j];
                            break;
                        }
                    }
                }
            }
        }
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            IExchangeAggregator.ExchangeToken
                memory exchangeToken = _exchangeTokens[i];
            if (exchangeToken.fromAmount > 0) {
                _exchange(
                    exchangeToken.fromToken,
                    exchangeToken.toToken,
                    exchangeToken.fromAmount,
                    exchangeToken.exchangeParam
                );
            }
        }
    }

    function exchangeAndSend(
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) external isKeeper {
        address sellToCopy = sellTo;
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            IExchangeAggregator.ExchangeToken
                memory exchangeToken = _exchangeTokens[i];
            require(
                exchangeToken.toToken == sellToCopy,
                "Rewards can only be sold as sellTo"
            );
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
        IExchangeAdapter.SwapDescription
            memory swapDescription = IExchangeAdapter.SwapDescription({
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
        emit Exchange(
            exchangeParam.platform,
            _fromToken,
            _amount,
            _toToken,
            exchangeAmount
        );
    }
}
