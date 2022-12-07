// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

/// @title IWhitelist interface
interface IWhitelist {
    event WhitelistRemoval(address indexed whitelist);
    event WhitelistAddition(address indexed whitelist);

    /// @dev Returns Whitelists.
    /// @return List of whitelist addresses.
    function getWhitelists() external view returns (address[] memory);

    /// @dev getter to determine if address is in whitelist
    function isWhitelisted(address _whitelist) external view returns (bool _found);

    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param _whitelist Address of new whitelist address.
    function addAddressToWhitelist(address _whitelist) external returns (bool _success);

    /// @dev add addresses to the whitelist
    /// @param _whitelists addresses
    /// @return _success true if at least one address was added to the whitelist,
    ///  false if all addresses were already in the whitelist
    function addAddressesToWhitelist(address[] memory _whitelists) external returns (bool _success);

    /// @dev remove an address from the whitelist
    /// @param _whitelist address
    /// @return _success true if the address was removed from the whitelist,
    /// false if the address wasn't in the whitelist in the first place
    function removeAddressFromWhitelist(address _whitelist) external returns (bool _success);

    /// @dev remove addresses from the whitelist
    /// @param _whitelists addresses
    /// @return _success true if at least one address was removed from the whitelist,
    /// false if all addresses weren't in the whitelist in the first place
    function removeAddressesFromWhitelist(address[] memory _whitelists) external returns (bool _success);
}
