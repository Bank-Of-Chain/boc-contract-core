// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "../exchanges/IExchangeAggregator.sol";
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

    /// @param _platforms Called exchange platforms
    /// @param _fromTokens The token swap from
    /// @param _fromAmounts The amount In to swap
    /// @param _exchangeAmounts The return amount of this swap
    /// @param _toToken The token swap to
    event Exchange(
        address[] _platforms,
        address[] _fromTokens,
        uint256[] _fromAmounts,
        uint256[] _exchangeAmounts,
        address _toToken
    );

    function usdStrategiesLenth() external view returns (uint256);

    function ethStrategiesLenth() external view returns (uint256);

    function findUsdItem(uint256 _index) external view returns (IterableSellInfoMap.SellInfo memory);

    function findEthItem(uint256 _index) external view returns (IterableSellInfoMap.SellInfo memory);

    /// @notice Recover tokens stuck in contract, i.e. transfer by mistaken.
    /// @dev Transfer token to governor.
    /// @param _asset Address for the asset
    /// @param _amount Amount of the asset to transfer
    function transferToken(address _asset, uint256 _amount) external;

    /// @notice Collect the reward token from strategy.
    /// @param _strategies The target strategies
    function collectUsdStrategies(address[] calldata _strategies) external;

    /// @notice Collect the reward token from strategy.
    /// @param _strategies The target strategies
    function collectEthStrategies(address[] calldata _strategies) external;

    /// @notice Collect the reward token when strategy was redeemed.
    /// @param _vault The vault of the strategy
    function strategyRedeemCollect(address _vault) external;

    /// @notice Exchange USD strategy's reward token to sellTo,and send to recipient
    /// @param _strategy The target strategy
    /// @param _exchangeTokens The exchange info
    function exchangeUsdStrategyReward(
        address _strategy,
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) external;

    /// @notice Exchange ETH strategy's reward token to sellTo,and send to recipient
    /// @param _strategy The target strategy
    /// @param _exchangeTokens The exchange info
    function exchangeEthStrategyReward(
        address _strategy,
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) external;
}
