// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./IWhitelist.sol";
import "./../access-control/AccessControlMixin.sol";

/// @title Whitelist
/// @notice The Whitelist contract has a whitelist of addresses, and provides basic authorization control functions.
/// @notice This simplifies the implementation of "user permissions".
/// @author Bank of Chain Protocol Inc
contract Whitelist is IWhitelist, AccessControlMixin, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet internal whitelistSet;

    /// @notice Initialize
    /// @param _accessControlProxy The access control proxy address
    function initialize(address _accessControlProxy) external initializer {
        _initAccessControl(_accessControlProxy);
    }

    /// @dev Returns Whitelists.
    /// @return List of whitelist addresses.
    function getWhitelists() external view override returns (address[] memory) {
        return whitelistSet.values();
    }

    /// @dev getter to determine if address is in whitelist
    function isWhitelisted(address _account) external view override returns (bool _found) {
        _found = whitelistSet.contains(_account);
        return _found;
    }

    /// @dev add addresses to the whitelist
    /// @param _accounts address list of the whitelist addresses.
    function addAddressesToWhitelist(address[] memory _accounts) external override isVaultManager {
        uint256 _accountsLength = _accounts.length;
        for (uint256 i = 0; i < _accountsLength; i++) {
            address _account = _accounts[i];
            if (!whitelistSet.contains(_account)) {
                whitelistSet.add(_account);
                emit WhitelistAddition(_account);
            }
        }
    }

    /// @dev remove addresses from the whitelist
    /// @param _accounts address list of the whitelist addresses.
    function removeAddressesFromWhitelist(address[] memory _accounts) external override isVaultManager {
        uint256 _accountsLength = _accounts.length;
        for (uint256 i = 0; i < _accountsLength; i++) {
            address _account = _accounts[i];
            if (whitelistSet.contains(_account)) {
                whitelistSet.remove(_account);
                emit WhitelistRemoval(_account);
            }
        }
    }
}
