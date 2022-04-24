// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "../access-control/AccessControlMixin.sol";
import "../library/IterableIntMap.sol";
import "../library/StableMath.sol";
import "../token/USDi.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract VaultStorage is
    Initializable,
    ReentrancyGuardUpgradeable,
    AccessControlMixin
{
    using StableMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using IterableIntMap for IterableIntMap.AddressToIntMap;

    struct StrategyParams {
        //last report timestamp
        uint256 lastReport;
        //total asset
        uint256 totalDebt;
        uint256 profitLimitRatio;
        uint256 lossLimitRatio;
        bool enforceChangeLimit;
    }

    struct StrategyAdd {
        address strategy;
        uint256 profitLimitRatio;
        uint256 lossLimitRatio;
    }

    event AddAsset(address _asset);
    event RemoveAsset(address _asset);
    event AddStrategies(address[] _strategies);
    event RemoveStrategies(address[] _strategies);
    event RemoveStrategyByForce(address _strategy);
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
        uint256 _actualAmount
    );
    event BurnWithoutExchange(
        address _account,
        address[] _assets,
        uint256[] _amounts,
        uint256 _burnAmount
    );
    event Exchange(
        address _platform,
        address _srcAsset,
        uint256 _srcAmount,
        address _distAsset,
        uint256 _distAmount
    );
    event Redeem(
        address _strategy,
        uint256 _debtChangeAmount,
        address[] _assets,
        uint256[] _amounts
    );
    event LendToStrategy(
        address indexed strategy,
        address[] wants,
        uint256[] amounts,
        uint256 lendValue
    );
    event RepayFromStrategy(
        address indexed strategy,
        uint256 strategyWithdrawValue,
        uint256 strategyTotalValue,
        address[] _assets,
        uint256[] _amounts
    );
    event StrategyReported(
        address indexed strategy,
        uint256 gain,
        uint256 loss,
        uint256 lastStrategyTotalDebt,
        uint256 nowStrategyTotalDebt,
        address[] _rewardTokens,
        uint256[] _claimAmounts
    );
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

    //max percentage 100%
    uint256 internal constant MAX_BPS = 10000;

    // usdi
    USDi internal usdi;

    // all strategy
    EnumerableSet.AddressSet internal strategySet;
    // Assets supported by the Vault, i.e. Stablecoins
    EnumerableSet.AddressSet internal assetSet;
    // Assets held by Vault
    IterableIntMap.AddressToIntMap internal trackedAssetsMap;
    // Decimals of the assets held by Vault
    mapping(address => uint256) internal trackedAssetDecimalsMap;

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
    //all strategy asset
    uint256 public totalDebt;
    // treasury contract that can collect a percentage of yield
    address public treasury;
    //valueInterpreter
    address public valueInterpreter;
    //exchangeManager
    address public exchangeManager;
    // strategy info
    mapping(address => StrategyParams) public strategies;

    //withdraw strategy set
    address[] public withdrawQueue;
    //keccak256("USDi.vault.governor.admin.impl");
    bytes32 constant adminImplPosition =
        0x3d78d3961e16fde088e2e26c1cfa163f5f8bb870709088dd68c87eb4091137e2;

    /**
     * @dev set the implementation for the admin, this needs to be in a base class else we cannot set it
     * @param newImpl address of the implementation
     */
    function setAdminImpl(address newImpl) external onlyGovOrDelegate {
        require(
            AddressUpgradeable.isContract(newImpl),
            "new implementation is not a contract"
        );
        bytes32 position = adminImplPosition;
        assembly {
            sstore(position, newImpl)
        }
    }
}
