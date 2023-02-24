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
import "./../strategy/IClaimableStrategy.sol";
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

    IterableSellInfoMap.AddressToSellInfoMap private usdStrategyCollection;
    IterableSellInfoMap.AddressToSellInfoMap private ethStrategyCollection;

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
        return usdStrategyCollection.length();
    }

    function ethStrategiesLenth() external view override returns (uint256) {
        return ethStrategyCollection.length();
    }

    function findUsdItem(
        uint256 _index
    ) external view override returns (IterableSellInfoMap.SellInfo memory) {
        (, IterableSellInfoMap.SellInfo memory _sellInfo) = usdStrategyCollection.at(_index);
        return _sellInfo;
    }

    function findEthItem(
        uint256 _index
    ) external view override returns (IterableSellInfoMap.SellInfo memory) {
        (, IterableSellInfoMap.SellInfo memory _sellInfo) = ethStrategyCollection.at(_index);
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

        emit TransferToken(msg.sender, _asset, _amount);
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

    /// @notice Collect the reward token when strategy was redeemed.
    /// @param _vault The vault of the strategy
    function strategyRedeemCollect(address _vault) external {
        require(_vault == usdVaultAddress || _vault == ethVaultAddress);

        IterableSellInfoMap.AddressToSellInfoMap storage _collection = _vault == usdVaultAddress
            ? usdStrategyCollection
            : ethStrategyCollection;
        _collectStrategy(_vault, msg.sender, _collection);
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
        IterableSellInfoMap.AddressToSellInfoMap storage _collection = _vault == usdVaultAddress
            ? usdStrategyCollection
            : ethStrategyCollection;
        // require(strategies.length() == 0, "The sale list has not been processed");
        for (uint256 i = 0; i < _strategies.length; i++) {
            address _strategy = _strategies[i];
            _collectStrategy(_vault, _strategy, _collection);
        }
    }

    function _collectStrategy(
        address _vault,
        address _strategy,
        IterableSellInfoMap.AddressToSellInfoMap storage _collection
    ) internal {
        IVault(_vault).checkActiveStrategy(_strategy);
        (
            address[] memory _rewardTokens,
            uint256[] memory _rewardAmounts,
            address _sellTo,
            bool _needReInvest
        ) = IClaimableStrategy(_strategy).collectReward();
        address _recipient = _needReInvest ? _strategy : _vault;

        IterableSellInfoMap.SellInfo memory _sellInfo = _collection.get(_strategy);
        if (_sellInfo.strategy != address(0)) {
            require(_sellInfo.rewardTokens.length == _rewardTokens.length);
            for (uint i = 0; i < _rewardAmounts.length; i++) {
                _sellInfo.rewardAmounts[i] += _rewardAmounts[i];
            }
            // use new recipient replace old recipient
            if (_sellInfo.recipient != _recipient) {
                _sellInfo.recipient = _recipient;
            }
        } else {
            _sellInfo.strategy = _strategy;
            _sellInfo.rewardTokens = _rewardTokens;
            _sellInfo.rewardAmounts = _rewardAmounts;
            _sellInfo.sellToToken = _sellTo;
            _sellInfo.recipient = _recipient;
        }
        _collection.set(_strategy, _sellInfo);

        emit CollectStrategyReward(_strategy, _rewardTokens, _rewardAmounts, _sellTo, _recipient);
    }

    function _exchangeStrategyReward(
        address _vault,
        address _strategy,
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) internal {
        require(_vault == usdVaultAddress || _vault == ethVaultAddress);
        IterableSellInfoMap.AddressToSellInfoMap storage strategies = _vault == usdVaultAddress
            ? usdStrategyCollection
            : ethStrategyCollection;
        IterableSellInfoMap.SellInfo memory sellInfo = strategies.get(_strategy);
        uint256 _sellToAmount = 0;
        uint256 exchangeRound = _exchangeTokens.length;
        address[] memory _platforms = new address[](exchangeRound);
        address[] memory _fromTokens = new address[](exchangeRound);
        uint256[] memory _fromTokenAmounts = new uint256[](exchangeRound);
        uint256[] memory _toTokenAmounts = new uint256[](exchangeRound);
        for (uint256 i = 0; i < exchangeRound; i++) {
            IExchangeAggregator.ExchangeToken memory _exchangeToken = _exchangeTokens[i];
            require(_exchangeToken.toToken == sellInfo.sellToToken, "Rewards can only be sold as sellTo");
            uint256 _exchangeAmount = _exchange(
                _exchangeToken.fromToken,
                _exchangeToken.toToken,
                _exchangeToken.fromAmount,
                sellInfo.recipient,
                _exchangeToken.exchangeParam
            );
            _platforms[i] = _exchangeToken.exchangeParam.platform;
            _fromTokens[i] = _exchangeToken.fromToken;
            _fromTokenAmounts[i] = _exchangeToken.fromAmount;
            _toTokenAmounts[i] = _exchangeAmount;
            _sellToAmount += _exchangeAmount;
        }
        
        if (sellInfo.strategy == sellInfo.recipient){
            IClaimableStrategy(_strategy).exchangeFinishCallback(_sellToAmount);
        }

        strategies.remove(_strategy);

        emit Exchange(
            _strategy,
            _platforms,
            _fromTokens,
            _fromTokenAmounts,
            _toTokenAmounts,
            sellInfo.sellToToken
        );
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
    }
}
