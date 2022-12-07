// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./IWhitelist.sol";
import "./../access-control/AccessControlMixin.sol";
import "./../library/BocRoles.sol";

/// @title Whitelist
/// @notice The Whitelist contract has a whitelist of addresses, and provides basic authorization control functions.
/// @notice This simplifies the implementation of "user permissions".
/// @author Bank of Chain Protocol Inc
contract Whitelist is IWhitelist, AccessControlMixin, Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet internal whitelistSet;

    /// @notice Initialize
    /// @param _accessControlProxy  The access control proxy address
    function initialize(address _accessControlProxy) external initializer {
        _initAccessControl(_accessControlProxy);
    }

    /// @dev Returns Whitelists.
    /// @return List of whitelist addresses.
    function getWhitelists() external view override returns (address[] memory) {
        return whitelistSet.values();
    }

    /// @dev getter to determine if address is in whitelist
    function isWhitelisted(address _whitelist) external view override returns (bool _found) {
        _found = whitelistSet.contains(_whitelist);
        return _found;
    }

    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param _whitelist Address of new whitelist address.
    /// @return _success true if the address was added to the whitelist, false if the address was already in the whitelist
    function addAddressToWhitelist(address _whitelist)
        public
        override
        isVaultManager
        returns (bool _success)
    {
        if (!whitelistSet.contains(_whitelist)) {
            whitelistSet.add(_whitelist);
            emit WhitelistAddition(_whitelist);
            _success = true;
        }
    }

    /// @dev add addresses to the whitelist
    /// @param _whitelists addresses
    /// @return _success true if at least one address was added to the whitelist,
    ///  false if all addresses were already in the whitelist
    function addAddressesToWhitelist(address[] memory _whitelists)
        external
        override
        isVaultManager
        returns (bool _success)
    {
        for (uint256 i = 0; i < _whitelists.length; i++) {
            if (addAddressToWhitelist(_whitelists[i])) {
                _success = true;
            }
        }
    }

    /// @dev remove an address from the whitelist
    /// @param _whitelist address
    /// @return _success true if the address was removed from the whitelist,
    /// false if the address wasn't in the whitelist in the first place
    function removeAddressFromWhitelist(address _whitelist)
        public
        override
        isVaultManager
        returns (bool _success)
    {
        if (whitelistSet.contains(_whitelist)) {
            whitelistSet.remove(_whitelist);
            emit WhitelistRemoval(_whitelist);
            _success = true;
        }
    }

    /// @dev remove addresses from the whitelist
    /// @param _whitelists addresses
    /// @return _success true if at least one address was removed from the whitelist,
    /// false if all addresses weren't in the whitelist in the first place
    function removeAddressesFromWhitelist(address[] memory _whitelists)
        external
        override
        isVaultManager
        returns (bool _success)
    {
        for (uint256 i = 0; i < _whitelists.length; i++) {
            if (removeAddressFromWhitelist(_whitelists[i])) {
                _success = true;
            }
        }
    }
}
