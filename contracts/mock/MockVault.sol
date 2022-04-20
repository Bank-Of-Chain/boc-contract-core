// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import "./../access-control/AccessControlMixin.sol";
import "../strategy/IStrategy.sol";
import "hardhat/console.sol";

contract MockVault is AccessControlMixin {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    constructor(address _accessControlProxy){
        _initAccessControl(_accessControlProxy);
    }

    function burn(uint256 _amount) external {}

    function lend(
        address _strategy,
        address[] memory _assets,
        uint256[] memory _amounts
    ) external {
        for (uint8 i = 0; i < _assets.length; i++) {
            address token = _assets[i];
            uint256 amount = _amounts[i];
            IERC20Upgradeable item = IERC20Upgradeable(token);
            console.log('balance:%d,amount:%d',item.balanceOf(address(this)),amount);
            require(
                item.balanceOf(address(this)) >= amount,
                "Insufficient tokens"
            );
            item.safeTransfer(_strategy, amount);
        }
        IStrategy(_strategy).borrow(_assets,_amounts);

    }

    /// @notice Withdraw the funds from specified strategy.
    function redeem(address _strategy, uint256 _usdValue) external {
        uint totalValue = IStrategy(_strategy).estimatedTotalAssets();
        if (_usdValue > totalValue){
            _usdValue = totalValue;
        }
        IStrategy(_strategy).repay(_usdValue,totalValue);
    }

    /// @notice Strategy report asset
    function report(uint256 _strategyAsset) external {}

    function rebase() external {
        
    }
}
