// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "./../exchanges/ExchangeHelper.sol";
import "../library/IterableSellInfoMap.sol";

/// @title IHarvester interface
interface IHarvester {
    /// @param _sender The manager address
    /// @param _token The transfer token
    /// @param _amount The transfer amount
    event TransferToken(address indexed _sender, address indexed _token, uint256 _amount);

    /// @param _strategy The traget strategy
    /// @param _rewardTokens The reward token array
    /// @param _rewardAmounts The reward amounts
    /// @param _sellTo The token swap to
    /// @param _recipient The receiver address
    event CollectStrategyReward(
        address indexed _strategy,
        address[] _rewardTokens,
        uint256[] _rewardAmounts,
        address _sellTo,
        address _recipient
    );

    /// @param _strategy The collect reward strategy
    /// @param _platforms Called exchange platforms
    /// @param _fromTokens The token swap from
    /// @param _fromAmounts The amount In to swap
    /// @param _exchangeAmounts The return amount of this swap
    /// @param _toToken The token swap to
    event Exchange(
        address _strategy,
        ExchangeHelper.ExchangePlatform[] _platforms,
        address[] _fromTokens,
        uint256[] _fromAmounts,
        uint256[] _exchangeAmounts,
        address _toToken
    );

    function strategiesLength(address _vault) external view returns (uint256 _length);

    function findItem(
        address _vault,
        uint256 _index
    ) external view returns (IterableSellInfoMap.SellInfo memory _sellInfo);

    /// @notice Recover tokens stuck in contract, i.e. transfer by mistaken.
    /// @dev Transfer token to governor.
    /// @param _asset Address for the asset
    /// @param _amount Amount of the asset to transfer
    function transferToken(address _asset, uint256 _amount) external;

    /// @notice Collect the reward token from strategy.
    /// @param _vault The vault of the strategy
    /// @param _strategies The target strategies
    function collectStrategies(address _vault, address[] calldata _strategies) external;

    /// @notice Collect the reward token when strategy was redeemed.
    /// @param _vault The vault of the strategy
    function strategyRedeemCollect(address _vault) external;

    /// @notice Exchange strategy's reward token to sellTo,and send to recipient
    /// @param _vault The vault of the strategy
    /// @param _strategy The target strategy
    /// @param _exchangeParams The exchange info
    function exchangeStrategyReward(
        address _vault,
        address _strategy,
        ExchangeHelper.ExchangeParams[] calldata _exchangeParams
    ) external;
}
