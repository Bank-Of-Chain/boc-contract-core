pragma solidity ^0.8.0;

import "../exchanges/IExchangeAggregator.sol";

interface IHarvester {
    event Collected(address _strategy, address _rewardToken, uint256 _amount);
    event Exchange(
        address fromToken,
        uint256 fromAmount,
        address toToken,
        uint256 exchangeAmount
    );
    event ReceiverChanged(address _receiver);
    event SellToChanged(address _sellTo);
    event TransferToReceiver(
        address _receiver,
        address[] _assets,
        uint256[] _amounts
    );

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
