// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {NativeToken} from "../library/NativeToken.sol";

abstract contract AssetHelpers {
    using SafeERC20 for IERC20;

    function __isNativeToken(address _token) internal pure returns (bool) {
        return _token == NativeToken.NATIVE_TOKEN;
    }

    /// @dev Returns the symbol of a token at a given address.
    /// @param _token Address of a token
    /// @return Symbol of the token at the given address as a string in memory.
    function __getSymbol(address _token) internal view returns (string memory) {
        if (__isNativeToken(_token)) {
            return "ETH";
        }
        string memory _symbol = IERC20Metadata(_token).symbol();
        return _symbol;
    }

    /// @notice Fetch the `decimals()` from an ERC20 token
    /// @dev Grabs the `decimals()` from a contract and fails if
    ///     the decimal value does not live within a certain range
    /// @param _token Address of the ERC20 token
    /// @return uint256 Decimals of the ERC20 token
    function __getDecimals(address _token) internal view returns (uint256) {
        if (__isNativeToken(_token)) {
            return 18;
        }
        uint256 _decimals = IERC20Metadata(_token).decimals();
        require(_decimals > 0, "Token must have sufficient decimal places");

        return _decimals;
    }

    /// @dev Retrieve the balance of a given token at a specified account address.
    /// @param _token The address of the token to check.
    /// @param _account The address of the account to check.
    /// @return The balance of the given token at the
    function __balanceOfToken(address _token, address _account) internal view returns (uint256) {
        uint256 _balance;
        if (__isNativeToken(_token)) {
            _balance = _account.balance;
        } else {
            _balance = IERC20(_token).balanceOf(_account);
        }
        return _balance;
    }

    /// @dev Helper to approve a target account with the max amount of an asset.
    /// This is helpful for fully trusted contracts, such as adapters that
    /// interact with external protocol like Uniswap, Compound, etc.
    function __approveAssetMaxAsNeeded(address _asset, address _target, uint256 _neededAmount) internal {
        if (IERC20(_asset).allowance(address(this), _target) < _neededAmount) {
            IERC20(_asset).safeApprove(_target, 0);
            IERC20(_asset).safeApprove(_target, _neededAmount);
        }
    }

    
    /// @dev __transferToken is an internal function that is responsible for transfering tokens from one address to another. 
    /// @param _asset: The address of the asset to be transfered 
    /// @param _amount: The amount of the asset to be transfered 
    /// @param _recipient: The address of the recipient 
    function __transferToken(address _asset, uint256 _amount, address _recipient) internal {
        if (__isNativeToken(_asset)) {
            // if recipient is ZeppelinTransparentProxy contract，recive will fail.
            // slither-disable-next-line low-level-calls
            (bool succ, ) = _recipient.call{value: _amount}("");
            require(succ, "Failed to send Ether");
        } else {
            IERC20(_asset).safeTransfer(_recipient, _amount);
        }
    }
}
