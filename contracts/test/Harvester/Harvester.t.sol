// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "brain-forge-std/Test.sol";

import "../../library/NativeToken.sol";
import "../../vault/IVault.sol";
import "../../Harvester/Harvester.sol";
import "../../treasury/Treasury.sol";
import "../Constants.sol";
import "../../mock/Mock3rdPool.sol";
import "../../mock/MockStrategy.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HarvesterTest is Test {
    Harvester harvester;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address accessControlProxy = 0x94c0AA94Ef3aD19E3947e58a855636b38aDe53e0;
    address exchangeManager = 0x921FE3dF4F2073f0d4d0B839B6068460397a04f9;
    address usdVault = 0x30D120f80D60E7b58CA9fFaf1aaB1815f000B7c3;
    address ethVault = 0x8f0Cb368C63fbEDF7a90E43fE50F7eb8B9411746;
    address treasuryAddress;

    function setUp() public {

        Treasury treasury = new Treasury();
        treasury.initialize(accessControlProxy);
        treasuryAddress = address(treasury);
        harvester = new Harvester();

        harvester.initialize(accessControlProxy, treasuryAddress, exchangeManager, usdVault, ethVault);
    }

    function test_01_transferToken() public {
        uint256 wethBalance = 100 ether;
        uint256 ethBalance = 2 ether;
        deal(WETH, address(harvester), wethBalance);
        vm.deal(address(harvester),ethBalance);
        vm.deal(GOVERNANOR,123 ether);
        console2.log('harvester balance:',address(harvester).balance);
        console2.log('governanor balance:',GOVERNANOR.balance);

        uint256 beforeTransfer = IERC20(WETH).balanceOf(treasuryAddress);
        vm.startPrank(GOVERNANOR);
        harvester.transferToken(WETH, wethBalance);
        uint256 afterTransfer = IERC20(WETH).balanceOf(treasuryAddress);

        assertEq(afterTransfer - beforeTransfer, wethBalance);

        uint256 beforeTransferBalance = treasuryAddress.balance;
        harvester.transferToken(NativeToken.NATIVE_TOKEN, ethBalance);
        vm.stopPrank();
        uint256 afterTransferBalance = treasuryAddress.balance;

        assertEq(afterTransferBalance - beforeTransferBalance, ethBalance);
    }

    function test_02_collectUsdStrategies() public {
        vm.mockCall(address(0),abi.encodeWithSelector(Mock3rdPool.underlyingToken.selector),abi.encode(WETH));
        MockStrategy mockStrategy = new MockStrategy();
        mockStrategy.initialize(usdVault, address(harvester), address(0));
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = WETH;
        uint256 rewardAmount = 123 ether;
        uint256[] memory _rewardAmounts = new uint256[](1);
        _rewardAmounts[0] = rewardAmount;
        vm.mockCall(
            usdVault,
            abi.encodeWithSelector(IVault(usdVault).checkActiveStrategy.selector, address(mockStrategy)),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockStrategy),
            abi.encodeWithSelector(mockStrategy.collectReward.selector),
            abi.encode( _rewardTokens, _rewardAmounts,USDT, true)
        );
        address[] memory pendingToClaim = new address[](1);
        pendingToClaim[0] = address(mockStrategy);
        vm.prank(KEEPER);
        harvester.collectUsdStrategies(pendingToClaim);
        vm.clearMockedCalls();

        assertEq(harvester.usdStrategiesLenth(),1);

        IterableSellInfoMap.SellInfo memory _sellInfo = harvester.findUsdItem(0);
        assertEq(_sellInfo.strategy,address(mockStrategy));
        assertEq(_sellInfo.rewardTokens[0],WETH);
        assertEq(_sellInfo.rewardAmounts[0],rewardAmount);
        assertEq(_sellInfo.sellToToken,USDT);
        assertEq(_sellInfo.recipient,address(mockStrategy));
    }

    function test_03_collectEthStrategies() public {
        // for mcok strategy init
        vm.mockCall(address(0),abi.encodeWithSelector(Mock3rdPool.underlyingToken.selector),abi.encode(WETH));
        vm.mockCall(address(ethVault),abi.encodeWithSelector(IVault.valueInterpreter.selector),abi.encode(0xE4153088577C2D634CB4b3451Aa4ab7E7281ef1f));
        MockStrategy mockStrategy = new MockStrategy();
        mockStrategy.initialize(ethVault, address(harvester), address(0));
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = WETH;
        uint256 rewardAmount = 123 ether;
        uint256[] memory _rewardAmounts = new uint256[](1);
        _rewardAmounts[0] = rewardAmount;
        vm.mockCall(
            ethVault,
            abi.encodeWithSelector(IVault(ethVault).checkActiveStrategy.selector, address(mockStrategy)),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockStrategy),
            abi.encodeWithSelector(mockStrategy.collectReward.selector),
            abi.encode( _rewardTokens, _rewardAmounts,USDT, false)
        );
        address[] memory pendingToClaim = new address[](1);
        pendingToClaim[0] = address(mockStrategy);
        vm.prank(KEEPER);
        harvester.collectEthStrategies(pendingToClaim);
        vm.clearMockedCalls();

        assertEq(harvester.ethStrategiesLenth(),1);

        IterableSellInfoMap.SellInfo memory _sellInfo = harvester.findEthItem(0);
        assertEq(_sellInfo.strategy,address(mockStrategy));
        assertEq(_sellInfo.rewardTokens[0],WETH);
        assertEq(_sellInfo.rewardAmounts[0],rewardAmount);
        assertEq(_sellInfo.sellToToken,USDT);
        assertEq(_sellInfo.recipient,ethVault);
    }
}
