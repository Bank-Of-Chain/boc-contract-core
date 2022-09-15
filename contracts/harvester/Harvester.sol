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


/// @title Harvester
/// @notice Harvester for function used by keeper
/// @author Bank of Chain Protocol Inc
contract Harvester is IHarvester, AccessControlMixin, Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The receiving address of profit
    address public profitReceiver;
    /// @notice The manager of exchange
    address public exchangeManager;
    /// @notice The return token when sell rewards 
    address public sellTo;
    /// @notice The vault address
    address public vaultAddress;

    /// @notice Initialize
    /// @param _accessControlProxy  The access control proxy address
    /// @param _receiver The receiving address of profit
    /// @param _sellTo The return token when sell rewards 
    /// @param _vault The vault address
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

    /// @dev Only governance role can call
    /// @inheritdoc IHarvester
    function setProfitReceiver(address _receiver) external override onlyRole(BocRoles.GOV_ROLE) {
        require(_receiver != address(0), "Must be a non-zero address");
        profitReceiver = _receiver;

        emit ReceiverChanged(profitReceiver);
    }
    
    /// @inheritdoc IHarvester
    function setSellTo(address _sellTo) external override isVaultManager {
        require(_sellTo != address(0), "Must be a non-zero address");
        sellTo = _sellTo;

        emit SellToChanged(sellTo);
    }

    /// @inheritdoc IHarvester
    function transferToken(address _asset, uint256 _amount)
        external
        override
        onlyRole(BocRoles.GOV_ROLE)
    {
        IERC20Upgradeable(_asset).safeTransfer(IVault(vaultAddress).treasury(), _amount);
    }

    /// @dev Only Keeper can call
    /// @inheritdoc IHarvester
    function collect(address[] calldata _strategies) external override isKeeper {
        for (uint256 i = 0; i < _strategies.length; i++) {
            address _strategy = _strategies[i];
            IVault(vaultAddress).checkActiveStrategy(_strategy);
            IStrategy(_strategy).harvest();
        }
    }

    /// @dev Only Keeper can call
    /// @inheritdoc IHarvester
    function exchangeAndSend(IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens)
        external
        override
        isKeeper
    {
        address _sellToCopy = sellTo;
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            IExchangeAggregator.ExchangeToken memory _exchangeToken = _exchangeTokens[i];
            require(_exchangeToken.toToken == _sellToCopy, "Rewards can Only be sold as sellTo");
            _exchange(
                _exchangeToken.fromToken,
                _exchangeToken.toToken,
                _exchangeToken.fromAmount,
                _exchangeToken.exchangeParam
            );
        }
    }

    /// @notice Exchange from all reward tokens to 'sellTo' token(one stablecoin)
    /// @param _fromToken The token swap from
    /// @param _toToken The token swap to
    /// @param _amount The amount to swap
    /// @param _exchangeParam The struct of ExchangeParam, see {ExchangeParam} struct
    /// @return _exchangeAmount The return amount of 'sellTo' token on this exchange
    /// Emits a {Exchange} event.
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
        IERC20Upgradeable(_fromToken).safeApprove(exchangeManager, 0);
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
