// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "../exchanges/IExchangeAggregator.sol";

/// @title IHarvester interface
interface IHarvester {

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

    /// @param _receiver The profit receive address 
    event ReceiverChanged(address _receiver);

    /// @param _sellTo The return token when sell rewards
    event SellToChanged(address _sellTo);

    /// @notice Sets profit receiving address
    /// @param _receiver The profit receive address 
    function setProfitReceiver(address _receiver) external;

    /// @notice Sets the return token when sell rewards 
    /// @param _sellTo The new return token when sell rewards
    function setSellTo(address _sellTo) external;

    /// @notice Multi strategies harvest and collect all rewards to this contarct
    /// @param _strategies The multi strategies to harvest
    function collect(address[] calldata _strategies) external;

    /// @notice After collect all rewards,exchange from all reward tokens to 'sellTo' token(one stablecoin),finally send stablecoin to receiver
    /// @param _exchangeTokens The all exchange info will be used
    function exchangeAndSend(IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens) external;

    /// @notice Recover tokens stuck in contract, i.e. transfer by mistaken.
    /// @dev Transfer token to governor.
    /// @param _asset Address for the asset
    /// @param _amount Amount of the asset to transfer
    function transferToken(address _asset, uint256 _amount) external;
}
