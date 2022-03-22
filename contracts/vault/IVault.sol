// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../exchanges/IExchangeAggregator.sol";

interface IVault {
    event AddAsset(address _asset);
    event RemoveAsset(address _asset);
    event AddStrategies(address[] _strategies);
    event RemoveStrategies(address[] _strategies);
    event Mint(
        address _account,
        address[] _assets,
        uint256[] _amounts,
        uint256 _mintAmount
    );
    event Burn(
        address _account,
        address[] _assets,
        uint256[] _amounts,
        uint256 _burnAmount
    );
    event Exchange(
        address _srcAsset,
        uint256 _srcAmount,
        address _distAsset,
        address _distAmount
    );
    event Redeem(address _strategy, uint256 _amount);
    event SetEmergencyShutdown(bool _shutdown);

    /// @notice Version of vault
    function getVersion() external pure returns (string memory);

    /// @notice Minting USDi supported assets
    function getSupportAssets() external view returns (address[] memory assets);

    /// @notice Assets held by Vault
    function getTrackedAssets() external view returns (address[] memory assets);

    /// @notice Vault holds asset value directly in USD
    function valueOfTrackedTokens() external view returns (uint256 totalValue);

    /// @notice Vault total asset in USD
    function totalAssets() external view returns (uint256);

    /// @notice Address of treasury
    function treasury() external view returns (address);

    /// @notice Address of price oracle
    function valueInterpreter() external view returns (address);

    /// @notice All strategies
    function getStrategies()
        external
        view
        returns (address[] memory strategies);

    /// @notice Calculate the number of stablecoins that burn shares can return
    function calculateRedeemOutputs(uint256 _amount)
        external
        view
        returns (uint256[] memory);

    /// @notice Added support for specific asset.
    function addAsset(address _asset) external;

    /// @notice Remove support for specific asset.
    function removeAsset(address _asset) external;

    /// @notice Add strategy to strategy list
    /// @dev The strategy added to the strategy list,
    ///      Vault may invest funds into the strategy,
    ///      and the strategy will invest the funds in the 3rd protocol
    function addStrategy(address[] memory _strategies) external;

    /// @notice Remove strategy from strategy list
    /// @dev The removed policy withdraws funds from the 3rd protocol and returns to the Vault
    function removeStrategy(address[] memory _strategies) external;

    /// @notice Minting USDi with stablecoins
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @dev Support single asset or multi-assets
    function mint(address[] memory _assets, uint256[] memory _amounts) external;

    /// @notice burn USDi,return stablecoins
    /// @param _amount Amount of USDi to burn
    function burn(uint256 _amount) external;

    /// @notice Change USDi supply with Vault total assets.
    function rebase() external;

    /// @notice Allocate funds in Vault to strategies.
    function lend(
        address _strategy,
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) external;

    /// @notice Withdraw the funds from specified strategy.
    function redeem(address _strategy, uint256 _amount) external;

    /// @notice Strategy report asset
    function report(uint256 _strategyAsset) external;

    /// @notice Shutdown the vault when an emergency occurs, cannot mint/burn.
    function setEmergencyShutdown(bool active) external;
}
