// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategy {

    event MigarteToNewVault(address _oldVault,address _newVault);
    event Harvest(uint256 _beforeAssets,uint256 _afterAssets,address _rewardToken,uint256 _claimAmount);
    event Deposit(address[] _assets, uint256[] _amounts);
    event Withdraw(uint256 _withdrawShares,uint256 _totalShares,address[] _assets, uint256[] _amounts);

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

    /// @notice Migarte to new vault
    function setVault(address vaultAddress) external;

    /// @notice Harvester address
    function harvester() external view returns (address);

    /// @notice Provide the strategy need underlying token and ratio
    /// @dev If ratio is 0, it means that the ratio of the token is free.
    function getWantsInfo() external view returns (address[] memory assets,uint[] memory ratios);

    /// @notice Total assets of strategy in USD.
    function estimatedTotalAssets() external view returns (uint256);

    /// @notice 3rd prototcol's pool total assets in USD.
    function get3rdPoolAssets() external view returns (uint256);

    /// @notice Provide a signal to the keeper that `harvest()` should be called.
    /// @param _rewardsToken reward token.
    /// @param _pendingAmount pending reward amount.
    function getPendingRewards() external view returns (address _rewardsToken,uint256 _pendingAmount);

    /// @notice Harvests the Strategy, recognizing any profits or losses and adjusting the Strategy's position.
    function harvest() external;

    /// @notice Vault deposit funds to strategy
    /// @param _assets Deposit token address
    /// @param _amounts Deposit token amount
    function deposit(address[] memory _assets, uint256[] memory _amounts) external;

    /// @notice Vault withdraw funds from strategy
    /// @param _withdrawShares Numerator
    /// @param _totalShares Denominator
    function withdraw(uint256 _withdrawShares,uint256 _totalShares) external;



}
