// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "../exchanges/IExchangeAggregator.sol";

interface IHarvester {

    /// @notice Setting profit receive address.
    function setProfitReceiver(address _receiver) external;

    /// @notice Setting sell to token.
    function setSellTo(address _sellTo) external;

    /// @notice Collect reward tokens from all strategies
    function collect(address[] calldata _strategies) external;

    /// @notice Swap reward token to stablecoins
    function exchangeAndSend(
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) external;

    // function sendAssetsToReceiver(
    //     address[] memory _assets,
    //     uint256[] memory _amounts
    // ) external;
}
