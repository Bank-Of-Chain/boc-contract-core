// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./../access-control/AccessControlMixin.sol";
import "./../library/BocRoles.sol";
import "./../strategy/IStrategy.sol";
import "./../vault/IVault.sol";

/**
 * @title USDI Dripper
 *
 * The dripper contract smooths out the yield from point-in-time yield events
 * and spreads the yield out over a configurable time period. This ensures a
 * continuous per block yield to makes users happy as their next rebase
 * amount is always moving up. Also, this makes historical day to day yields
 * smooth, rather than going from a near zero day, to a large APY day, then
 * back to a near zero day again.
 *
 *
 * Design notes
 * - USDT has a smaller resolution than the number of seconds
 * in a week, which can make per block payouts have a rounding error. However
 * the total effect is not large - cents per day, and this money is
 * not lost, just distributed in the future. While we could use a higher
 * decimal precision for the drip perBlock, we chose simpler code.
 * - By calculating the changing drip rates on collects only, harvests and yield
 * events don't have to call anything on this contract or pay any extra gas.
 * Collect() is already be paying for a single write, since it has to reset
 * the lastCollect time.
 * - By having a collectAndRebase method, and having our external systems call
 * that, the USDI vault does not need any changes, not even to know the address
 * of the dripper.
 * - A rejected design was to retro-calculate the drip rate on each collect,
 * based on the balance at the time of the collect. While this would have
 * required less state, and would also have made the contract respond more quickly
 * to new income, it would break the predictability that is this contract's entire
 * purpose. If we did this, the amount of fundsAvailable() would make sharp increases
 * when funds were deposited.
 * - When the dripper recalculates the rate, it targets spending the balance over
 * the duration. This means that every time that collect is is called, if no
 * new funds have been deposited the duration is being pushed back and the
 * rate decreases. This is expected, and ends up following a smoother but
 * longer curve the more collect() is called without incoming yield.
 *
 */
contract Dripper is AccessControlMixin, Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @param _durationSeconds the new duration to drip
    event DripDurationChanged(uint256 _durationSeconds);
    /// @param _token the new token to drip out
    event TokenChanged(address _token);
    /// @param _token the new token to drip out
    /// @param _amount The amount collected
    event Collection(address _token, uint256 _amount);
    
   
    /// @param lastCollect The timestamp of last collection, will overflows 262 billion years after the sun dies
    /// @param perBlock The drip rate per block
    struct Drip {
        uint64 lastCollect; 
        uint192 perBlock;
    }

    /// @notice USDI vault
    address public vault; 
    /// @notice token to drip out
    address public token; 
    /// @notice the duration to drip in seconds
    uint256 public dripDuration; 
    /// @notice active drip parameters
    Drip public drip; 

    /// @notice Initialize
    /// @param _accessControlProxy The access control proxy address
    /// @param _vault The vault address
    /// @param _token The token to drip out
    function initialize(
        address _accessControlProxy,
        address _vault,
        address _token
    ) external initializer {
        require(_vault != address(0), "Must be a non-zero address");
        require(_token != address(0), "Must be a non-zero address");

        vault = _vault;
        token = _token;
        _initAccessControl(_accessControlProxy);
    }

    /// @notice Return The available amount to sent currently
    function availableFunds() external view returns (uint256) {
        uint256 _balance = IERC20Upgradeable(token).balanceOf(address(this));
        return _availableFunds(_balance, drip);
    }

    /// @notice Collect all dripped funds, send to vault and recalculate new drip rate
    function collect() external {
        _collect();
    }

    /// @notice Collect all dripped funds, send to vault, recalculate new drip rate, and rebase USDI.
    function collectAndRebase() external {
        _collect();
        IVault(vault).rebase();
    }

    /// @notice Set the new drip duration. Governor call only
    /// @dev Drip out the entire balance over if no collects were called during that time
    /// @param _durationSeconds the new drip duration in seconds 
    function setDripDuration(uint256 _durationSeconds) external isVaultManager {
        require(_durationSeconds > 0, "duration must be non-zero");
        dripDuration = uint192(_durationSeconds);
        _collect(); // duration change take immediate effect
        emit DripDurationChanged(dripDuration);
    }

    /// @notice Sets new token to drip out
    function setToken(address _token) external isVaultManager {
        require(_token != address(0), "Must be a non-zero address");
        token = _token;
        emit TokenChanged(_token);
    }

    /// @notice Transfer ERC20 tokens to treasury. Governor call only
    /// @param _asset ERC20 token address
    /// @param _amount amount to transfer
    function transferToken(address _asset, uint256 _amount) external onlyRole(BocRoles.GOV_ROLE) {
        IERC20Upgradeable(_asset).safeTransfer(IVault(vault).treasury(), _amount);
    }

    /// @notice Calculate available funds by taking the lower of either the
    ///  currently dripped out funds or the balance available.
    ///  Uses passed in parameters to calculate with for gas savings.
    /// @param _balance current balance in contract
    /// @param _drip current drip parameters
    /// @return the available funds
    function _availableFunds(uint256 _balance, Drip memory _drip) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - _drip.lastCollect;
        uint256 allowed = (elapsed * _drip.perBlock);
        return (allowed > _balance) ? _balance : allowed;
    }

    /// @notice Sends the currently dripped funds to be vault, and sets
    ///  the new drip rate based on the new balance.
    function _collect() internal {
        // Calculate send
        uint256 _balance = IERC20Upgradeable(token).balanceOf(address(this));
        uint256 _amountToSend = _availableFunds(_balance, drip);
        uint256 _remaining = _balance - _amountToSend;
        // Calculate new drip perBlock
        // Gas savings by setting entire struct at one time
        drip = Drip({perBlock: uint192(_remaining / dripDuration), lastCollect: uint64(block.timestamp)});
        // Send funds
        IERC20Upgradeable(token).safeTransfer(vault, _amountToSend);
        emit Collection(token, _amountToSend);
    }
}
