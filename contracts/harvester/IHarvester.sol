pragma solidity ^0.8.0;

import "../exchanges/IExchangeAggregator.sol";

interface IHarvester {

    event Collected(address _strategy,address _rewardToken,uint _amount);
    event TransferToVault(address _asset,uint _amount);

    /// @notice Collect reward tokens from all strategies
    function harvest(address[] calldata _strategies) external;

    /// @notice Swap reward token to stablecoins
    function swap(IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens) external;

     /// @notice Transfer token to vault
     /// @param _asset Address for the asset
     /// @param _amount Amount of the asset to transfer
    function transferTokenVault(address _asset, uint _amount) external;
}