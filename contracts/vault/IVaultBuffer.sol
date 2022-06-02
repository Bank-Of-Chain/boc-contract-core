// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IVaultBuffer {
    
    
    /// @notice estimate amount of pending shares
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @return mintAmount pendingShares amount
    function estimateMint(address[] memory _assets, uint256[] memory _amounts)
        external
        view
        returns (uint256 mintAmount);
   
    /// @notice mint pending shares
    /// @param _sender user account address
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @return mintAmount pendingShares amount
    function mint(address _sender,address[] memory _assets, uint256[] memory _amounts)
        external
        returns (uint256 mintAmount);

    /// @notice transfer cash to vault
    /// @param _assets transfer token
    /// @param _amounts transfer token amount
    function prepareToLend(address[] memory _assets, uint256[] memory _amounts) external;

    /// @notice distribute USDi to users that pendingShare's holder.
    function distribute() external;

    /// @notice use USDi swap cash,when old user want to withdraw.
    /// @param usdiAmount usdi amount,in
    /// @param expectToken expect token ,out
    /// @return _assets actual out assets.
    /// @return _amounts actual out token amounts.
    function swapCash(uint256 usdiAmount,address expectToken)
        external
        returns (address[] memory _assets, uint256[] memory _amounts);
} 