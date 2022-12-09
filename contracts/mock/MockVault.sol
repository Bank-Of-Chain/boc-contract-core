// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./../access-control/AccessControlMixin.sol";
import "../strategy/IStrategy.sol";

contract MockVault is AccessControlMixin {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    constructor(address _accessControlProxy) {
        _initAccessControl(_accessControlProxy);
    }

    function burn(uint256 _amount) external {}

    function lend(
        address _strategy,
        address[] memory _assets,
        uint256[] memory _amounts
    ) external {
        for (uint8 i = 0; i < _assets.length; i++) {
            address _token = _assets[i];
            uint256 _amount = _amounts[i];
            IERC20Upgradeable _item = IERC20Upgradeable(_token);
            require(_item.balanceOf(address(this)) >= _amount, "Insufficient tokens");
            _item.safeTransfer(_strategy, _amount);
        }
        IStrategy(_strategy).borrow(_assets, _amounts);
    }

    /// @notice Withdraw the funds from specified strategy.
    function redeem(
        address _strategy,
        uint256 _usdValue,
        uint256 _outputCode
    ) external {
        uint256 _totalValue = IStrategy(_strategy).estimatedTotalAssets();
        if (_usdValue > _totalValue) {
            _usdValue = _totalValue;
        }
        IStrategy(_strategy).repay(_usdValue, _totalValue, _outputCode);
    }

    /// @notice Strategy report asset
    function report(uint256 _strategyAsset) external {}

    function rebase() external {}
}
