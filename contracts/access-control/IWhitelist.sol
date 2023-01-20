// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

/// @title IWhitelist interface
interface IWhitelist {
    event WhitelistRemoval(address[] _accounts);
    event WhitelistAddition(address[] _accounts);

    /// @dev Returns Whitelists.
    /// @return List of whitelist addresses.
    function getWhitelists() external view returns (address[] memory);

    /// @dev getter to determine if address is in whitelist
    function isWhitelisted(address _account) external view returns (bool _found);

    /// @dev add addresses to the whitelist
    /// @param _accounts address list of the whitelist addresses.
    function addAddressesToWhitelist(address[] memory _accounts) external;

    /// @dev remove addresses from the whitelist
    /// @param _accounts address list of the whitelist addresses.
    function removeAddressesFromWhitelist(address[] memory _accounts) external;
}
