// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "../exchanges/IExchangeAggregator.sol";
import "../library/IterableSellInfoMap.sol";

/// @title IHarvester interface
interface IHarvester {
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

    /// @param _platform Called exchange platforms
    /// @param _fromToken The token swap from
    /// @param _fromAmount The amount In to swap
    /// @param _toToken The token swap to
    /// @param _exchangeAmount The return amount of this swap
    event Exchange(
        address _platform,
        address _fromToken,
        uint256 _fromAmount,
        address _toToken,
        uint256 _exchangeAmount
    );

    // /// @notice Sets profit receiving address
    // /// @param _receiver The profit receive address
    // function setProfitReceiver(address _receiver) external;

    // /// @notice Sets the return token when sell rewards
    // /// @param _sellTo The new return token when sell rewards
    // function setSellTo(address _sellTo) external;

    // /// @notice Multi strategies harvest and collect all rewards to this contarct
    // /// @param _strategies The multi strategies to harvest
    // function collect(address[] calldata _strategies) external;

    // /// @notice After collect all rewards,exchange from all reward tokens to 'sellTo' token(one stablecoin),finally send stablecoin to receiver
    // /// @param _exchangeTokens The all exchange info will be used
    // function exchangeAndSend(IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens) external;

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
