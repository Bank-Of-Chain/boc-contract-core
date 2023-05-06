// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IHarvester.sol";
import "./../library/BocRoles.sol";
import "../vault/IVault.sol";
import "./../strategy/IClaimableStrategy.sol";

/// @title Harvester
/// @notice Harvester for function used by keeper
/// @author Bank of Chain Protocol Inc
contract Harvester is IHarvester, ExchangeHelper {
    using SafeERC20 for IERC20;
    using IterableSellInfoMap for IterableSellInfoMap.AddressToSellInfoMap;

    /// @notice The addres of Treasury
    address public treasuryAddress;
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
    /// @param _usdVault The USD vault address
    /// @param _ethVault The ETH vault address
    function initialize(
        address _accessControlProxy,
        address _treasury,
        address _usdVault,
        address _ethVault
    ) external initializer {
        require(_treasury != address(0), "Must be a non-zero address");
        require(_usdVault != address(0), "Must be a non-zero address");
        require(_ethVault != address(0), "Must be a non-zero address");
        treasuryAddress = _treasury;
        usdVaultAddress = _usdVault;
        ethVaultAddress = _ethVault;

        __InitializeRouters();

        _initAccessControl(_accessControlProxy);
    }

    function strategiesLength(address _vault) external view override returns (uint256 _length) {
        if (_vault == usdVaultAddress) {
            _length = usdStrategyCollection.length();
        } else if (_vault == ethVaultAddress) {
            _length = ethStrategyCollection.length();
        }
    }

    function findItem(
        address _vault,
        uint256 _index
    ) external view override returns (IterableSellInfoMap.SellInfo memory _sellInfo) {
        if (_vault == usdVaultAddress) {
            (, _sellInfo) = usdStrategyCollection.at(_index);
        } else if (_vault == ethVaultAddress) {
            (, _sellInfo) = ethStrategyCollection.at(_index);
        }
    }

    /// @inheritdoc IHarvester
    function transferTokenToTreasury(
        address _asset,
        uint256 _amount
    ) external override onlyRole(BocRoles.GOV_ROLE) {
        __transferToken(_asset, _amount, treasuryAddress);

        emit TransferTokenToTreasury(msg.sender, _asset, _amount);
    }

    /// @notice Collect the reward token from strategy.
    /// @param _vault The vault of the strategy
    /// @param _strategies The target strategies
    function collectStrategies(
        address _vault,
        address[] calldata _strategies
    ) external override isKeeperOrVaultOrGovOrDelegate {
        require(_vault == usdVaultAddress || _vault == ethVaultAddress);
        IterableSellInfoMap.AddressToSellInfoMap storage _collection = _vault == usdVaultAddress
            ? usdStrategyCollection
            : ethStrategyCollection;
        // require(strategies.length() == 0, "The sale list has not been processed");
        for (uint256 i = 0; i < _strategies.length; i++) {
            address _strategy = _strategies[i];
            _collectStrategy(_vault, _strategy, false, _collection);
        }
    }

    /// @notice Collect the reward token when strategy was redeemed.
    /// @param _vault The vault of the strategy
    function strategyRedeemCollect(address _vault) external {
        require(_vault == usdVaultAddress || _vault == ethVaultAddress);

        IterableSellInfoMap.AddressToSellInfoMap storage _collection = _vault == usdVaultAddress
            ? usdStrategyCollection
            : ethStrategyCollection;
        _collectStrategy(_vault, msg.sender, true, _collection);
    }

    /// @notice Exchange strategy's reward token to sellTo,and send to recipient
    /// @param _vault The vault of the strategy
    /// @param _strategy The target strategy
    /// @param _exchangeParams The exchange info
    function exchangeStrategyReward(
        address _vault,
        address _strategy,
        ExchangeParams[] calldata _exchangeParams
    ) external override isKeeperOrVaultOrGovOrDelegate returns (uint256[] memory _receiveAmounts) {
        return _exchangeStrategyReward(_vault, _strategy, _exchangeParams);
    }

    function _collectStrategy(
        address _vault,
        address _strategy,
        bool _isRedeemCollect,
        IterableSellInfoMap.AddressToSellInfoMap storage _collection
    ) internal {
        IVault(_vault).checkActiveStrategy(_strategy);
        (
            address[] memory _rewardTokens,
            uint256[] memory _rewardAmounts,
            address _sellTo,
            bool _needReInvest
        ) = IClaimableStrategy(_strategy).collectReward();
        address _recipient = _isRedeemCollect ? _vault : _needReInvest ? _strategy : _vault;

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
        // slither-disable-next-line unused-return
        _collection.set(_strategy, _sellInfo);

        emit CollectStrategyReward(_strategy, _rewardTokens, _rewardAmounts, _sellTo, _recipient);
    }

    function _exchangeStrategyReward(
        address _vault,
        address _strategy,
        ExchangeHelper.ExchangeParams[] calldata _exchangeParams
    ) internal returns (uint256[] memory _receiveAmounts) {
        // Check if the vault is either USD or ETH
        require(_vault == usdVaultAddress || _vault == ethVaultAddress);
        // Get the strategies from the vault
        IterableSellInfoMap.AddressToSellInfoMap storage strategies = _vault == usdVaultAddress
            ? usdStrategyCollection
            : ethStrategyCollection;
        // Get the sell info
        IterableSellInfoMap.SellInfo memory sellInfo = strategies.get(_strategy);
        uint256 _sellToAmount = 0;
        uint256 exchangeRound = _exchangeParams.length;
        ExchangeHelper.ExchangePlatform[] memory _platforms = new ExchangeHelper.ExchangePlatform[](
            exchangeRound
        );
        _receiveAmounts = new uint256[](exchangeRound);
        address[] memory _fromTokens = new address[](exchangeRound);
        uint256[] memory _fromTokenAmounts = new uint256[](exchangeRound);
        uint256[] memory _toTokenAmounts = new uint256[](exchangeRound);
        for (uint256 i = 0; i < exchangeRound; i++) {
            ExchangeHelper.ExchangeParams memory _exchangeParam = _exchangeParams[i];
            // Check if the rewards can only be sold as sellTo
            require(_exchangeParam.toToken == sellInfo.sellToToken, "Rewards can only be sold as sellTo");
            // Check if the source token is sufficient
            require(
                _exchangeParam.fromAmount > 0 &&
                    _exchangeParam.fromAmount <=
                    __balanceOfToken(_exchangeParam.fromToken, address(this)),
                "Source token insufficient."
            );
            // Exchange the tokens
            uint256 _receiveAmount = _exchange(
                _exchangeParam.fromToken,
                _exchangeParam.toToken,
                _exchangeParam.fromAmount,
                _exchangeParam.txData,
                _exchangeParam.platform
            );
            // Store the receive amount
            _receiveAmounts[i] = _receiveAmount;
            // Transfer the receive amount to the recipient
            __transferToken(_exchangeParam.toToken, _receiveAmount, sellInfo.recipient);
            // Store the platform, from tokens, from token amounts and to token amounts
            _platforms[i] = _exchangeParam.platform;
            _fromTokens[i] = _exchangeParam.fromToken;
            _fromTokenAmounts[i] = _exchangeParam.fromAmount;
            _toTokenAmounts[i] = _receiveAmount;
            // Calculate the sell to amount
            _sellToAmount += _receiveAmount;
        }
        // Call the exchange finish callback
        IClaimableStrategy(_strategy).exchangeFinishCallback(_sellToAmount);
        // Remove the strategy
        // slither-disable-next-line unused-return
        strategies.remove(_strategy);
        // Emit the exchange event
        emit Exchange(
            _strategy,
            _platforms,
            _fromTokens,
            _fromTokenAmounts,
            _toTokenAmounts,
            sellInfo.sellToToken
        );
    }
}
