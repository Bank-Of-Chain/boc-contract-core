// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "./IPegToken.sol";

contract WrappedPegToken is ERC20Permit {
    IPegToken public pegToken;

    /**
     * @param _pegToken address of the peg token to wrap
     */
    constructor(
        IPegToken _pegToken,
        string memory _name,
        string memory _symbol
    ) public ERC20Permit(_name) ERC20(_name, _symbol) {
        pegToken = _pegToken;
    }

    function wrap(uint256 _underlyingUnits) external returns (uint256) {
        require(_underlyingUnits > 0, "can't wrap zero peg token");
        uint256 _wPegTokenAmount = pegToken.getSharesByUnderlyingUnits(_underlyingUnits);
        _mint(msg.sender, _wPegTokenAmount);
        pegToken.transferFrom(msg.sender, address(this), _underlyingUnits);
        return _wPegTokenAmount;
    }

    function unwrap(uint256 _wPegTokenAmount) external returns (uint256) {
        require(_wPegTokenAmount > 0, "zero amount unwrap not allowed");
        uint256 _pegTokenAmount = pegToken.getUnderlyingUnitsByShares(_wPegTokenAmount);
        _burn(msg.sender, _wPegTokenAmount);
        pegToken.transfer(msg.sender, _pegTokenAmount);
        return _pegTokenAmount;
    }

    function getWrapedPegTokenByPegToken(uint256 _pegTokenAmount) external view returns (uint256) {
        return pegToken.getSharesByUnderlyingUnits(_pegTokenAmount);
    }

    function getPegTokenByWrapedPegToken(uint256 _wPegTokenAmount) external view returns (uint256) {
        return pegToken.getUnderlyingUnitsByShares(_wPegTokenAmount);
    }

    function pegTokenPerToken() external view returns (uint256) {
        return pegToken.getUnderlyingUnitsByShares(1 ether);
    }

    function tokensPerPegToken() external view returns (uint256) {
        return pegToken.getSharesByUnderlyingUnits(1 ether);
    }
}
