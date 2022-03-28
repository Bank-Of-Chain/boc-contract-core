// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "hardhat/console.sol";
import "./IVault.sol";
import "../access-control/AccessControlMixin.sol";
import '../price-feeds/IValueInterpreter.sol';
import '../strategy/IStrategy.sol';
import '../library/IterableIntMap.sol';
import "../library/StableMath.sol";
import "../library/BocRoles.sol";
import "../token/USDi.sol";
import "../util/Helpers.sol";

import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract VaultStorage is Initializable, AccessControlMixin {

    using StableMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using IterableIntMap for IterableIntMap.AddressToIntMap;

    event AddAsset(address _asset);
    event RemoveAsset(address _asset);
    event AddStrategies(address[] _strategies);
    event RemoveStrategies(address[] _strategies);
    event Mint(
        address _account,
        address[] _assets,
        uint256[] _amounts,
        uint256 _mintAmount
    );
    event Burn(
        address _account,
        address _asset,
        uint256 _amount,
        uint256 _burnAmount
    );
    event BurnWithoutExchange(
        address _account,
        address[] _assets,
        uint256[] _amounts,
        uint256 _burnAmount
    );
    event Exchange(
        address _srcAsset,
        uint256 _srcAmount,
        address _distAsset,
        uint256 _distAmount
    );
    event Redeem(address _strategy, uint256 _amount);
    event RemoveStrategyFromQueue(address[] _strategies);
    event SetEmergencyShutdown(bool _shutdown);
    event RebasePaused();
    event RebaseUnpaused();
    event RebaseThresholdUpdated(uint256 _threshold);
    event MaxSupplyDiffChanged(uint256 maxSupplyDiff);
    event TrusteeFeeBpsChanged(uint256 _basis);
    event TreasuryAddressChanged(address _address);
    event SetAdjustPositionPeriod(bool _adjustPositionPeriod);
    event RedeemFeeUpdated(uint256 _redeemFeeBps);
    event SetWithdrawalQueue(address[] queues);

    address internal constant ZERO_ADDRESS = address(0);

    //最大百分比100%
    uint256 internal constant MAX_BPS = 10000;

    // usdi
    USDi internal usdi;

    // all strategy
    EnumerableSet.AddressSet internal strategySet;
    // Assets supported by the Vault, i.e. Stablecoins
    EnumerableSet.AddressSet internal assetSet;
    // Assets held by Vault
    IterableIntMap.AddressToIntMap internal trackedAssetsMap;

    //adjust Position Period
    bool public adjustPositionPeriod;
    // emergency shutdown
    bool public emergencyShutdown;
    // Pausing bools
    bool public rebasePaused;
    // Mints over this amount automatically rebase. 18 decimals.
    uint256 public rebaseThreshold;
    // allow max supply diff
    uint256 public maxSupplyDiff;
    // Amount of yield collected in basis points
    uint256 public trusteeFeeBps;
    // Redemption fee in basis points
    uint256 public redeemFeeBps;
    // treasury contract that can collect a percentage of yield
    address public treasury;
    //valueInterpreter
    address public valueInterpreter;
    //exchangeManager
    address public exchangeManager;
    //  Only whitelisted contracts can call our deposit
    mapping(address => bool) public whiteList;

    //withdraw strategy set
    address[] public withdrawQueue;
}
