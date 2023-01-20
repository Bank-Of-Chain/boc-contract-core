// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import { IBasicToken } from "../interface/IBasicToken.sol";

/// @title Helpers
/// @notice Helpers library for get symbol and decimals fo one token
library Helpers {
    /// @notice Fetch the `symbol()` from an ERC20 token
    /// @dev Grabs the `symbol()` from a contract
    /// @param _token Address of the ERC20 token
    /// @return string Symbol of the ERC20 token
    function getSymbol(address _token) internal view returns (string memory) {
        string memory _symbol = IBasicToken(_token).symbol();
        return _symbol;
    }

    /// @notice Fetch the `decimals()` from an ERC20 token
    /// @dev Grabs the `decimals()` from a contract and fails if
    ///     the decimal value does not live within a certain range
    /// @param _token Address of the ERC20 token
    /// @return uint256 Decimals of the ERC20 token
    function getDecimals(address _token) internal view returns (uint256) {
        uint256 _decimals = IBasicToken(_token).decimals();
        require(_decimals > 0, "Token must have sufficient decimal places");

        return _decimals;
    }
}
