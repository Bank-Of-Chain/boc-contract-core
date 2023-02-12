// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../library/NativeToken.sol";
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
    using IterableSellInfoMap for IterableSellInfoMap.AddressToSellInfoMap;

    /// @notice The addres of Treasury
    address public treasuryAddress;
    /// @notice The manager of exchange
    address public exchangeManager;
    /// @notice The USD vault address
    address public usdVaultAddress;
    /// @notice The ETH vault address
    address public ethVaultAddress;

    IterableSellInfoMap.AddressToSellInfoMap private usdStrategies;
    IterableSellInfoMap.AddressToSellInfoMap private ethStrategies;

    receive() external payable {}

    fallback() external payable {}

    /// @notice Initialize
    /// @param _accessControlProxy  The access control proxy address
    /// @param _treasury The address of Treasury
    /// @param _exchangeManager The address of Exchange Manager
    /// @param _usdVault The USD vault address
    /// @param _ethVault The ETH vault address
    function initialize(
        address _accessControlProxy,
        address _treasury,
        address _exchangeManager,
        address _usdVault,
        address _ethVault
    ) external initializer {
        require(_treasury != address(0), "Must be a non-zero address");
        require(_exchangeManager != address(0), "Must be a non-zero address");
        require(_usdVault != address(0), "Must be a non-zero address");
        require(_ethVault != address(0), "Must be a non-zero address");
        treasuryAddress = _treasury;
        exchangeManager = _exchangeManager;
        usdVaultAddress = _usdVault;
        ethVaultAddress = _ethVault;
        _initAccessControl(_accessControlProxy);
    }

    function usdStrategiesLenth() external view override returns (uint256) {
        return usdStrategies.length();
    }

    function ethStrategiesLenth() external view override returns (uint256) {
        return ethStrategies.length();
    }

    function findUsdItem(
        uint256 _index
    ) external view override returns (IterableSellInfoMap.SellInfo memory) {
        (, IterableSellInfoMap.SellInfo memory _sellInfo) = usdStrategies.at(_index);
        return _sellInfo;
    }

    function findEthItem(
        uint256 _index
    ) external view override returns (IterableSellInfoMap.SellInfo memory) {
        (, IterableSellInfoMap.SellInfo memory _sellInfo) = ethStrategies.at(_index);
        return _sellInfo;
    }

    /// @inheritdoc IHarvester
    function transferToken(
        address _asset,
        uint256 _amount
    ) external override onlyRole(BocRoles.GOV_ROLE) {
        if (_asset == NativeToken.NATIVE_TOKEN) {
            payable(treasuryAddress).transfer(_amount);
        } else {
            IERC20Upgradeable(_asset).safeTransfer(treasuryAddress, _amount);
        }
    }

    /// @notice Collect the reward token from strategy.
    /// @param _strategies The target strategies
    function collectUsdStrategies(
        address[] calldata _strategies
    ) external override isKeeperOrVaultOrGovOrDelegate {
        _collectStrategies(usdVaultAddress, _strategies);
    }

    /// @notice Collect the reward token from strategy.
    /// @param _strategies The target strategies
    function collectEthStrategies(
        address[] calldata _strategies
    ) external override isKeeperOrVaultOrGovOrDelegate {
        _collectStrategies(ethVaultAddress, _strategies);
    }

    /// @notice Exchange USD strategy's reward token to sellTo,and send to recipient
    /// @param _strategy The target strategy
    /// @param _exchangeTokens The exchange info
    function exchangeUsdStrategyReward(
        address _strategy,
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) external override isKeeperOrVaultOrGovOrDelegate {
        _exchangeStrategyReward(usdVaultAddress, _strategy, _exchangeTokens);
    }

    /// @notice Exchange ETH strategy's reward token to sellTo,and send to recipient
    /// @param _strategy The target strategy
    /// @param _exchangeTokens The exchange info
    function exchangeEthStrategyReward(
        address _strategy,
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) external override isKeeperOrVaultOrGovOrDelegate {
        _exchangeStrategyReward(ethVaultAddress, _strategy, _exchangeTokens);
    }

    function _collectStrategies(address _vault, address[] calldata _strategies) internal {
        require(_vault == usdVaultAddress || _vault == ethVaultAddress);
        IterableSellInfoMap.AddressToSellInfoMap storage strategies = _vault == usdVaultAddress
            ? usdStrategies
            : ethStrategies;
        require(strategies.length() == 0, "The sale list has not been processed");
        for (uint256 i = 0; i < _strategies.length; i++) {
            address _strategy = _strategies[i];
            IVault(_vault).checkActiveStrategy(_strategy);
            (
                address[] memory _rewardTokens,
                uint256[] memory _rewardAmounts,
                address _sellTo,
                bool _needReInvest
            ) = IStrategy(_strategy).collectReward();
            address _recipient = _needReInvest ? _strategy : _vault;
            IterableSellInfoMap.SellInfo memory sellInfo = IterableSellInfoMap.SellInfo(
                _strategy,
                _rewardTokens,
                _sellTo,
                _rewardAmounts,
                _recipient
            );
            strategies.set(_strategy, sellInfo);

            emit CollectStrategyReward(_strategy, _rewardTokens, _rewardAmounts, _sellTo, _recipient);
        }
    }

    function _exchangeStrategyReward(
        address _vault,
        address _strategy,
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) internal {
        require(_vault == usdVaultAddress || _vault == ethVaultAddress);
        IterableSellInfoMap.AddressToSellInfoMap storage strategies = _vault == usdVaultAddress
            ? usdStrategies
            : ethStrategies;
        IterableSellInfoMap.SellInfo memory sellInfo = strategies.get(_strategy);
        for (uint256 i = 0; i < _exchangeTokens.length; i++) {
            IExchangeAggregator.ExchangeToken memory _exchangeToken = _exchangeTokens[i];
            require(_exchangeToken.toToken == sellInfo.sellToToken, "Rewards can only be sold as sellTo");
            _exchange(
                _exchangeToken.fromToken,
                _exchangeToken.toToken,
                _exchangeToken.fromAmount,
                sellInfo.recipient,
                _exchangeToken.exchangeParam
            );
        }

        strategies.remove(_strategy);
    }

    /// @notice Exchange from all reward tokens to 'sellTo' token(one stablecoin)
    /// @param _fromToken The token swap from
    /// @param _toToken The token swap to
    /// @param _amount The amount to swap
    /// @param _recepient The receiver of sell to token
    /// @param _exchangeParam The struct of ExchangeParam, see {ExchangeParam} struct
    /// @return _exchangeAmount The return amount of 'sellTo' token on this exchange
    /// Emits a {Exchange} event.
    function _exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        address _recepient,
        IExchangeAggregator.ExchangeParam memory _exchangeParam
    ) internal returns (uint256 _exchangeAmount) {
        IExchangeAdapter.SwapDescription memory _swapDescription = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _fromToken,
            dstToken: _toToken,
            receiver: _recepient
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
