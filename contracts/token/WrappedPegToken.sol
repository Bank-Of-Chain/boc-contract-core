// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "./IPegToken.sol";

/// @title WrappedPegToken
/// @notice Allow the wrapping of PegToken into a wrapped token for governance or other function
/// @author Bank of Chain Protocol Inc
contract WrappedPegToken is ERC20Permit {

    /// @notice the interface of PegToken wrapped
    IPegToken public pegToken;

    /// @param _pegToken address of the peg token to wrap
    /// @param _name The name of this wrapped PegToken
    /// @param _symbol The symbol of this wrapped PegToken
    constructor(
        IPegToken _pegToken,
        string memory _name,
        string memory _symbol
    ) ERC20Permit(_name) ERC20(_name, _symbol) {
        pegToken = _pegToken;
    }

    /// @notice Wrap the underlying token 
    /// @dev Deposit the underlying token and mint 'wPegToken' to 'msg.sender'
    /// @param _underlyingUnits The amount of underlying token
    /// @return  The amount of 'wPegToken' minted
    function wrap(uint256 _underlyingUnits) external returns (uint256) {
        require(_underlyingUnits > 0, "can't wrap zero peg token");
        uint256 _wPegTokenAmount = pegToken.getSharesByUnderlyingUnits(_underlyingUnits);
        _mint(msg.sender, _wPegTokenAmount);
        pegToken.transferFrom(msg.sender, address(this), _underlyingUnits);
        return _wPegTokenAmount;
    }

    /// @notice Unwrap the 'wPegToken' 
    /// @dev Burn thewPegToken' and and transfer underlying token to 'msg.sender'
    /// @param _wPegTokenAmount The amount of 'wPegToken'
    /// @return  The amount of underlying token released
    function unwrap(uint256 _wPegTokenAmount) external returns (uint256) {
        require(_wPegTokenAmount > 0, "zero amount unwrap not allowed");
        uint256 _pegTokenAmount = pegToken.getUnderlyingUnitsByShares(_wPegTokenAmount);
        _burn(msg.sender, _wPegTokenAmount);
        pegToken.transfer(msg.sender, _pegTokenAmount);
        return _pegTokenAmount;
    }

    /// @notice Return the amount of shares token(WrapedPegToken) per PegToken.
    function getWrapedPegTokenByPegToken(uint256 _pegTokenAmount) external view returns (uint256) {
        return pegToken.getSharesByUnderlyingUnits(_pegTokenAmount);
    }

    /// @notice Return the amount of PegToken per '_wPegToken'(shares token ).
    function getPegTokenByWrapedPegToken(uint256 _wPegTokenAmount) external view returns (uint256) {
        return pegToken.getUnderlyingUnitsByShares(_wPegTokenAmount);
    }

    /// @notice Return the amount of PegToken per shares token.
    function pegTokenPerToken() external view returns (uint256) {
        return pegToken.getUnderlyingUnitsByShares(1 ether);
    }

    /// @notice Return the amount of shares token per PegToken.
    function tokensPerPegToken() external view returns (uint256) {
        return pegToken.getSharesByUnderlyingUnits(1 ether);
    }
}
