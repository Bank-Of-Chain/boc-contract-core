// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IStrategy {
    event MigrateToNewVault(address _oldVault, address _newVault);
    event Report(
        uint256 _beforeAssets,
        uint256 _afterAssets,
        address[] _rewardTokens,
        uint256[] _claimAmounts
    );
    event Borrow(address[] _assets, uint256[] _amounts);
    event Repay(
        uint256 _withdrawShares,
        uint256 _totalShares,
        address[] _assets,
        uint256[] _amounts
    );

    /// @notice Version of strategy
    function getVersion() external pure returns (string memory);

    /// @notice Name of strategy
    function name() external pure returns (string memory);

    /// @notice ID of strategy
    function protocol() external pure returns (uint16);

    /// @notice Status of strategy
    function isActive() external view returns (bool);

    /// @notice Vault address
    function vault() external view returns (address);

    /// @notice Migrate to new vault
    function setVault(address _vaultAddress) external;

    /// @notice Harvester address
    function harvester() external view returns (address);

    /// @notice Provide the strategy need underlying token and ratio
    function getWantsInfo()
        external
        view
        returns (address[] memory _assets, uint256[] memory _ratios);

    /// @notice Provide the strategy need underlying token
    function getWants() external view returns (address[] memory _wants);

    /// @notice Returns the position details of the strategy.
    function getPositionDetail()
        external
        view
        returns (
            address[] memory _tokens,
            uint256[] memory _amounts,
            bool isUsd,
            uint256 usdValue
        );

    /// @notice Total assets of strategy in USD.
    function estimatedTotalAssets() external view returns (uint256);

    /// @notice 3rd protocol's pool total assets in USD.
    function get3rdPoolAssets() external view returns (uint256);

    /// @notice Harvests the Strategy, recognizing any profits or losses and adjusting the Strategy's position.
    function harvest()
        external
        returns (
            address[] memory _rewardsTokens,
            uint256[] memory _claimAmounts
        );

    /// @notice asset in usd (1e18)
    function checkBalance() external view returns (uint256 assetsInUSD);

    /// @notice Strategy borrow funds from vault
    /// @param _assets borrow token address
    /// @param _amounts borrow token amount
    function borrow(address[] memory _assets, uint256[] memory _amounts)
        external;

    /// @notice Strategy repay the funds to vault
    /// @param _withdrawShares Numerator
    /// @param _totalShares Denominator
    function repay(uint256 _withdrawShares, uint256 _totalShares)
        external
        returns (address[] memory _assets, uint256[] memory _amounts);

    /// @notice getter isWantRatioIgnorable
    function isWantRatioIgnorable() external view returns (bool);
}
