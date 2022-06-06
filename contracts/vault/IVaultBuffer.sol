// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IVaultBuffer {

    /// @notice mint pending shares
    /// @param _sender user account address
    /// @param _amount mint amount
    function mint(address _sender, uint256 _amount) external;

    /// @notice transfer cash to vault
    /// @param _assets transfer token
    /// @param _amounts transfer token amount
    function transferCashToVault(address[] memory _assets, uint256[] memory _amounts) external;

    /// @notice distribute USDi to users that pendingShare's holder.
    function distribute() external;
}
