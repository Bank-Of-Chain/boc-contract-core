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
        address _fromToken,
        uint256 _fromAmount,
        address _toToken,
        uint256 _exchangeAmount
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

    /// @notice Setting profit receive address. Only governance role can call.
    function setProfitReceiver(address _receiver) external onlyRole(BocRoles.GOV_ROLE) {
        require(_receiver != address(0), "Must be a non-zero address");
        profitReceiver = _receiver;

        emit ReceiverChanged(profitReceiver);
    }
    
    /// @notice Setting sell to token.  Only vault manager can call.
    function setSellTo(address _sellTo) external isVaultManager {
        require(_sellTo != address(0), "Must be a non-zero address");
        sellTo = _sellTo;

        emit SellToChanged(sellTo);
    }

    /**
     * @dev Transfer token to governor. Intended for recovering tokens stuck in
     *      contract, i.e. mistaken sends.
     * @param _asset Address of the asset
     * @param _amount Amount of the asset to transfer
     */
    function transferToken(address _asset, uint256 _amount) external onlyRole(BocRoles.GOV_ROLE) {
        IERC20Upgradeable(_asset).safeTransfer(vault.treasury(), _amount);
    }

    /**
     * @dev Multi strategies harvest and collect all rewards to this contarct
     * @param _strategies The strategy array in which each strategy will harvest
     * Requirements: only Keeper can call
     */
    function collect(address[] calldata _strategies) external isKeeper {
        for (uint256 i = 0; i < _strategies.length; i++) {
            address _strategy = _strategies[i];
            vault.checkActiveStrategy(_strategy);
            IStrategy(_strategy).harvest();
        }
    }

    /**
     * @dev First multi strategies harvest and collect all rewards to this contarct, 
     * then swap from all reward tokens to 'sellTo' token(one stablecoin),
     * finally send stablecoin to receiver
     * @param _strategies The strategy array in which each strategy will harvest
     * @param _exchangeTokens The all info of exchange will be used when exchange
     * Requirements: only Keeper can call
     */
    function collectAndSwapAndSend(
        address[] calldata _strategies,
        IExchangeAggregator.ExchangeToken[] memory _exchangeTokens
    ) external isKeeper {
        address _sellToCopy = sellTo;
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            require(_exchangeTokens[i].toToken == _sellToCopy, "Rewards can only be sold as sellTo");
            _exchangeTokens[i].fromAmount = 0;
        }
        
        for (uint256 i = 0; i < _strategies.length; i++) {
            address _strategy = _strategies[i];
            vault.checkActiveStrategy(_strategy);
            (address[] memory _rewardsTokens, uint256[] memory _claimAmounts) = IStrategy(_strategy)
                .harvest();
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
            IExchangeAggregator.ExchangeToken memory _exchangeToken = _exchangeTokens[i];
            if (_exchangeToken.fromAmount > 0) {
                _exchange(
                    _exchangeToken.fromToken,
                    _exchangeToken.toToken,
                    _exchangeToken.fromAmount,
                    _exchangeToken.exchangeParam
                );
            }
        }
    }

    /**
     * @dev After collect all rewards,exchange from all reward tokens to 'sellTo' token(one stablecoin),
     * finally send stablecoin to receiver
     * @param _exchangeTokens The all info of exchange will be used when exchange
     * Requirements: only Keeper can call
     */
    function exchangeAndSend(IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens)
        external
        isKeeper
    {
        address _sellToCopy = sellTo;
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            IExchangeAggregator.ExchangeToken memory _exchangeToken = _exchangeTokens[i];
            require(_exchangeToken.toToken == _sellToCopy, "Rewards can only be sold as sellTo");
            _exchange(
                _exchangeToken.fromToken,
                _exchangeToken.toToken,
                _exchangeToken.fromAmount,
                _exchangeToken.exchangeParam
            );
        }
    }

    /**
     * @dev Exchange from all reward tokens to 'sellTo' token(one stablecoin)
     * @param _fromToken The token swap from
     * @param _toToken The token swap to
     * @param _amount The amount to swap
     * @param _exchangeParam The struct of ExchangeParam, see {ExchangeParam} struct
     * @return _exchangeAmount The real amount to exchange
     * Emits a {Exchange} event.
     */
    function _exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory _exchangeParam
    ) internal returns (uint256 _exchangeAmount) {
        IExchangeAdapter.SwapDescription memory _swapDescription = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _fromToken,
            dstToken: _toToken,
            receiver: profitReceiver
        });
        IERC20Upgradeable(_fromToken).safeApprove(exchangeManager, _amount);
        _exchangeAmount = IExchangeAggregator(exchangeManager).swap(
            _exchangeParam.platform,
            _exchangeParam.method,
            _exchangeParam.encodeExchangeArgs,
            _swapDescription
        );
        emit Exchange(_exchangeParam.platform, _fromToken, _amount, _toToken, _exchangeAmount);
    }
}
