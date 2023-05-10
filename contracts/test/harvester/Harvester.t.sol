// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../../library/NativeToken.sol";
import "../../vault/IVault.sol";
import "../../harvester/Harvester.sol";
import "../../treasury/Treasury.sol";
import "../Constants.sol";
import "../../mock/Mock3rdPool.sol";
import "../../mock/MockStrategy.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HarvesterTest is Test {
    Harvester harvester;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address accessControlProxy = 0x94c0AA94Ef3aD19E3947e58a855636b38aDe53e0;
    address usdVault = 0x30D120f80D60E7b58CA9fFaf1aaB1815f000B7c3;
    address ethVault = 0x8f0Cb368C63fbEDF7a90E43fE50F7eb8B9411746;
    address treasuryAddress;
    Treasury treasury;

    bytes txData1 =
        hex"e449022e0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000391c1cb6ba5562ab100000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000060594a405d53811d3bc4766596efd80fd545a270cfee7c08";

    function setUp() public {
        treasury = new Treasury();
        treasury.initialize(accessControlProxy);
        treasuryAddress = address(treasury);
        harvester = new Harvester();

        harvester.initialize(accessControlProxy, treasuryAddress, usdVault, ethVault);
    }

    function testInit() public {
        Harvester harvesterTwo = new Harvester();
        harvesterTwo.initialize(accessControlProxy, treasuryAddress, usdVault, ethVault);
    }

    function testFailInitTwice() public {
        Harvester harvesterTwo = new Harvester();
        harvesterTwo.initialize(accessControlProxy, treasuryAddress, usdVault, ethVault);
        harvesterTwo.initialize(accessControlProxy, treasuryAddress, usdVault, ethVault);
    }

    function test_01_transferToken() public {
        uint256 wethBalance = 100 ether;
        uint256 ethBalance = 2 ether;
        deal(WETH, address(harvester), wethBalance);
        vm.deal(address(harvester), ethBalance);
        vm.deal(GOVERNANOR, 123 ether);
        console2.log("harvester balance:", address(harvester).balance);
        console2.log("governanor balance:", GOVERNANOR.balance);

        uint256 beforeTransfer = IERC20(WETH).balanceOf(treasuryAddress);
        vm.startPrank(GOVERNANOR);
        harvester.transferTokenToTreasury(WETH, wethBalance);
        uint256 afterTransfer = IERC20(WETH).balanceOf(treasuryAddress);

        assertEq(afterTransfer - beforeTransfer, wethBalance);

        uint256 beforeTransferBalance = treasuryAddress.balance;
        harvester.transferTokenToTreasury(NativeToken.NATIVE_TOKEN, ethBalance);
        vm.stopPrank();
        uint256 afterTransferBalance = treasuryAddress.balance;

        assertEq(afterTransferBalance - beforeTransferBalance, ethBalance);
    }

    function test_02_collectUsdStrategies() public {
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(Mock3rdPool.underlyingToken.selector),
            abi.encode(WETH)
        );
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
            abi.encode(_rewardTokens, _rewardAmounts, USDT, true)
        );
        address[] memory pendingToClaim = new address[](1);
        pendingToClaim[0] = address(mockStrategy);
        vm.prank(KEEPER);
        harvester.collectStrategies(usdVault, pendingToClaim);

        assertEq(harvester.strategiesLength(usdVault), 1);

        IterableSellInfoMap.SellInfo memory _sellInfo = harvester.findItem(usdVault, 0);
        assertEq(_sellInfo.strategy, address(mockStrategy));
        assertEq(_sellInfo.rewardTokens[0], WETH);
        assertEq(_sellInfo.rewardAmounts[0], rewardAmount);
        assertEq(_sellInfo.sellToToken, USDT);
        assertEq(_sellInfo.recipient, address(mockStrategy));

        address[] memory _rewardTokens2 = new address[](1);
        _rewardTokens2[0] = WETH;
        uint256 rewardAmount2 = 123 ether;
        uint256[] memory _rewardAmounts2 = new uint256[](1);
        _rewardAmounts2[0] = rewardAmount2;
        vm.mockCall(
            usdVault,
            abi.encodeWithSelector(IVault(usdVault).checkActiveStrategy.selector, address(mockStrategy)),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockStrategy),
            abi.encodeWithSelector(mockStrategy.collectReward.selector),
            abi.encode(_rewardTokens2, _rewardAmounts2, USDT, false)
        );
        address[] memory pendingToClaim2 = new address[](1);
        pendingToClaim2[0] = address(mockStrategy);
        vm.prank(KEEPER);
        harvester.collectStrategies(usdVault, pendingToClaim2);

        assertEq(harvester.strategiesLength(usdVault), 1);
        IterableSellInfoMap.SellInfo memory _sellInfo2 = harvester.findItem(usdVault, 0);
        assertEq(_sellInfo2.rewardAmounts[0], rewardAmount + rewardAmount2);
        assertEq(_sellInfo2.recipient, address(usdVault));

        vm.clearMockedCalls();
    }

    function test_03_collectEthStrategies() public {
        // for mcok strategy init
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(Mock3rdPool.underlyingToken.selector),
            abi.encode(WETH)
        );
        vm.mockCall(
            address(ethVault),
            abi.encodeWithSelector(IVault.valueInterpreter.selector),
            abi.encode(0xE4153088577C2D634CB4b3451Aa4ab7E7281ef1f)
        );
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
            abi.encode(_rewardTokens, _rewardAmounts, USDT, false)
        );
        address[] memory pendingToClaim = new address[](1);
        pendingToClaim[0] = address(mockStrategy);
        vm.prank(KEEPER);
        harvester.collectStrategies(ethVault, pendingToClaim);
        vm.clearMockedCalls();

        assertEq(harvester.strategiesLength(ethVault), 1);

        IterableSellInfoMap.SellInfo memory _sellInfo = harvester.findItem(ethVault, 0);
        assertEq(_sellInfo.strategy, address(mockStrategy));
        assertEq(_sellInfo.rewardTokens[0], WETH);
        assertEq(_sellInfo.rewardAmounts[0], rewardAmount);
        assertEq(_sellInfo.sellToToken, USDT);
        assertEq(_sellInfo.recipient, ethVault);
    }

    function test_04_strategyRedeemCollect() public {
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(Mock3rdPool.underlyingToken.selector),
            abi.encode(WETH)
        );
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
            abi.encode(_rewardTokens, _rewardAmounts, USDT, true)
        );
        address[] memory pendingToClaim = new address[](1);
        pendingToClaim[0] = address(mockStrategy);

        vm.prank(address(mockStrategy));
        harvester.strategyRedeemCollect(usdVault);

        assertEq(harvester.strategiesLength(usdVault), 1);

        IterableSellInfoMap.SellInfo memory _sellInfo = harvester.findItem(usdVault, 0);
        assertEq(_sellInfo.strategy, address(mockStrategy));
        assertEq(_sellInfo.rewardTokens[0], WETH);
        assertEq(_sellInfo.rewardAmounts[0], rewardAmount);
        assertEq(_sellInfo.sellToToken, USDT);
        assertEq(_sellInfo.recipient, address(usdVault));
    }

    function test_05_exchangeReward() public {
        // for mcok strategy init
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(Mock3rdPool.underlyingToken.selector),
            abi.encode(WETH)
        );
        vm.mockCall(
            address(ethVault),
            abi.encodeWithSelector(IVault.valueInterpreter.selector),
            abi.encode(0xE4153088577C2D634CB4b3451Aa4ab7E7281ef1f)
        );
        MockStrategy mockStrategy = new MockStrategy();
        mockStrategy.initialize(ethVault, address(harvester), address(0));
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = WETH;
        uint256 rewardAmount = 1 ether;
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
            abi.encode(_rewardTokens, _rewardAmounts, DAI, true)
        );

        address[] memory pendingToClaim = new address[](1);
        pendingToClaim[0] = address(mockStrategy);
        vm.prank(KEEPER);
        harvester.collectStrategies(ethVault, pendingToClaim);
        deal(WETH, address(harvester), 1 ether);

        console.log("harvester address: ", address(harvester));
        ExchangeHelper.ExchangeParams[] memory exchangeParams = new ExchangeHelper.ExchangeParams[](1);
        exchangeParams[0].fromToken = WETH;
        exchangeParams[0].toToken = DAI;
        exchangeParams[0].fromAmount = 1 ether;
        exchangeParams[0].platform = ExchangeHelper.ExchangePlatform.ONE_INCH;
        exchangeParams[0].txData = txData1;

        vm.prank(KEEPER);
        harvester.exchangeStrategyReward(ethVault, address(mockStrategy), exchangeParams);

        console.log("DAI balance: ", IERC20(DAI).balanceOf(address(mockStrategy)));
    }
}
