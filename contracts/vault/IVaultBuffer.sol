// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

/// @title IVaultBuffer interface
interface IVaultBuffer {
    event OpenDistribute();
    event CloseDistribute();
    /// @param  _platform The platform used for the exchange
    /// @param _srcAsset The address of asset exchange from 
    /// @param _srcAmount The amount of asset exchange from 
    /// @param _distAsset The address of asset exchange to 
    /// @param _distAmount The amount of asset exchange to 
    event Exchange(
        address _platform,
        address _srcAsset,
        uint256 _srcAmount,
        address _distAsset,
        uint256 _distAmount
    );

    /// @notice mint pending shares
    /// @param _sender user account address
    /// @param _amount mint amount
    function mint(address _sender, uint256 _amount) external payable;

    /// @notice transfer cash to vault
    /// @param _assets transfer token
    /// @param _amounts transfer token amount
    function transferCashToVault(address[] memory _assets, uint256[] memory _amounts) external;

    /// @notice Open the switch of distribution
    function openDistribute() external;

    /// @notice Distributes if the switch of distribution is 'true'
    function distributeWhenDistributing() external returns (bool);

    /// @notice Distributes once
    function distributeOnce() external returns (bool);

    /// @notice Return the boolean value of `isDistributing`
    function isDistributing() external view returns (bool);

    /// @notice Return the value of `mDistributeLimit`
    function getDistributeLimit() external view returns (uint256);

    /// @notice Sets '_limit' to the `mDistributeLimit` state
    function setDistributeLimit(uint256 _limit) external;
}
