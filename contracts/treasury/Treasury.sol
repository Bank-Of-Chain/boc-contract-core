// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '../access-control/AccessControlMixin.sol';
import '../library/BocRoles.sol';
import "../token/USDi.sol";

contract Treasury is Initializable, AccessControlMixin {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // usdi
    USDi internal usdi;
    function initialize(address _accessControlProxy,address _usdi) public initializer {
        _initAccessControl(_accessControlProxy);
        usdi = USDi(_usdi);
        usdi.rebaseOptIn();
    }

    // accepts ether
    receive() external payable {}

    fallback() external payable {}

    function version() public pure returns (string memory){
        return 'V1.0.2';
    }

    function balance(address _token) public view returns (uint256) {
        return IERC20Upgradeable(_token).balanceOf(address(this));
    }

    function withdraw(
        address _token,
        address _destination,
        uint256 _amount
    ) external onlyRole(BocRoles.GOV_ROLE) {
        require(_amount <= balance(_token), '!insufficient');
        IERC20Upgradeable(_token).safeTransfer(_destination, _amount);
    }

    function withdrawETH(address payable _destination, uint256 _amount)
    external
    payable
    onlyRole(BocRoles.GOV_ROLE) {
        _destination.transfer(_amount);
    }
}
