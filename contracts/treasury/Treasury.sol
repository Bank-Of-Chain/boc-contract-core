// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../access-control/AccessControlMixin.sol";
import "../library/BocRoles.sol";

/// @title Treasury
/// @notice The treasury contract mainly used to store public assets of the protocol
/// @author Bank of Chain Protocol Inc
contract Treasury is Initializable, ReentrancyGuardUpgradeable, AccessControlMixin {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize(address _accessControlProxy) external initializer {
        _initAccessControl(_accessControlProxy);
    }

    // accepts ether
    receive() external payable {}

    fallback() external payable {}

    /// @notice Return the current version of this contract.
    function version() external pure returns (string memory) {
        return "V1.0.0";
    }

    /// @notice Return the '_token' balance of this contract.
    function balance(address _token) public view returns (uint256) {
        return IERC20Upgradeable(_token).balanceOf(address(this));
    }

    /// @notice Withdraw '_amount' '_token' from this contract to '_destination'
    /// @param _token The token to withdraw
    /// @param _destination The destination address to withdraw
    /// @param _amount The amount of token to withdraw
    /// Requirements: only governance role can call
    function withdraw(
        address _token,
        address _destination,
        uint256 _amount
    ) external onlyRole(BocRoles.GOV_ROLE) {
        require(_amount <= balance(_token), "!insufficient");
        IERC20Upgradeable(_token).safeTransfer(_destination, _amount);
    }

    /// @notice Withdraw ETH from this contract to '_destination'
    /// @param _destination The destination address to withdraw
    /// @param _amount The amount of ETH to withdraw
    /// Requirements: only governance role can call
    function withdrawETH(
        address payable _destination,
        uint256 _amount
    ) external payable nonReentrant onlyRole(BocRoles.GOV_ROLE) {
        require(_destination != address(0), "destination is null");
        _destination.transfer(_amount);
    }
}
