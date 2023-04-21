// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "brain-forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../access-control/AccessControlProxy.sol";
import "../../library/NativeToken.sol";
import "../../vault/IVault.sol";
import "../../harvester/Harvester.sol";
import "../../treasury/Treasury.sol";
import "../Constants.sol";

import "../../vault/VaultBuffer.sol";
import "../../token/PegToken.sol";

contract VaultBufferTest is Test {
    PegToken pegToken;
    VaultBuffer vaultBuffer;

    address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    bytes txData1 = hex"e449022e0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000391c1cb6ba5562ab100000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000060594a405d53811d3bc4766596efd80fd545a270cfee7c08";
    // copy from https://cn.etherscan.com/tx/0xa8a80056e01222e2608781dedca8988c22a5f2ea6a7867a87f55fba832c66df3
    bytes txData2 = hex"0b86a4c1000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000003dae3c788199a8fb62000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000001000000000000000000004de494b86ca6f7a495930fe7f552eb9e4cbb5ef2b736";

    function setUp() public {
        AccessControlProxy accessControlProxy = new AccessControlProxy();
        accessControlProxy.initialize(GOVERNANOR, DEGEGATOR, VAULT_MANAGER, KEEPER);
        pegToken = new PegToken();
        pegToken.initialize("PegToken", "P", 18, address(this), address(accessControlProxy));

        vaultBuffer = new VaultBuffer();
        vaultBuffer.initialize(
            "Ticket",
            "T",
            address(this),
            address(pegToken),
            address(accessControlProxy)
        );
    }

    function testMint(uint256 _shares) public {
        vaultBuffer.mint(USER, _shares);

        assertEq(vaultBuffer.balanceOf(USER), _shares);
    }

    function testERC20Features() public {
        // pegToken's balanceOf method depends on the underlyingUnitsPerShare
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(IVault.underlyingUnitsPerShare.selector),
            abi.encode(1e18)
        );

        assertEq(vaultBuffer.name(), "Ticket", "name correct");
        assertEq(vaultBuffer.symbol(), "T", "symbol correct");
        assertEq(vaultBuffer.decimals(), 18, "decimals correct");

        uint userShares = 100 * 1e18;
        uint friendShares = 200 * 1e18;
        vaultBuffer.mint(USER, userShares);
        vaultBuffer.mint(FRIEND, friendShares);

        assertEq(vaultBuffer.totalSupply(), userShares + friendShares, "totalSupply correct");

        vm.prank(FRIEND);
        vaultBuffer.transfer(USER, 50 * 1e18);
        assertEq(vaultBuffer.balanceOf(USER), 150 * 1e18, "balanceOf correct1");
        assertEq(vaultBuffer.balanceOf(FRIEND), 150 * 1e18, "balanceOf correct2");

        vm.prank(USER);
        vaultBuffer.approve(FRIEND, 150 * 1e18);
        assertEq(vaultBuffer.allowance(USER, FRIEND), 150 * 1e18, "allowance correct1");

        vm.prank(USER);
        vaultBuffer.increaseAllowance(FRIEND, 500 * 1e18);
        assertEq(vaultBuffer.allowance(USER, FRIEND), 650 * 1e18, "allowance correct2");
        vm.prank(USER);
        vaultBuffer.decreaseAllowance(FRIEND, 500 * 1e18);
        assertEq(vaultBuffer.allowance(USER, FRIEND), 150 * 1e18, "allowance correct3");

        vm.prank(FRIEND);
        vaultBuffer.transferFrom(USER, FRIEND, 150 * 1e18);
        assertEq(vaultBuffer.balanceOf(USER), 0, "balanceOf correct3");
        assertEq(vaultBuffer.balanceOf(FRIEND), 300 * 1e18, "balanceOf correct4");
    }

    function testSetDistributeLimit(uint256 _limit) public {
        _limit = bound(_limit, 1, 1e4);
        vm.prank(VAULT_MANAGER);
        vaultBuffer.setDistributeLimit(_limit);

        assertEq(vaultBuffer.getDistributeLimit(), _limit);
    }

    function testTransferCashToVault(uint _usdtAmount, uint _usdcAmount, uint _daiAmount) public {
        // top up for VaultBuffer
        deal(USDT, address(vaultBuffer), _usdtAmount);
        deal(USDC, address(vaultBuffer), _usdcAmount);
        deal(DAI, address(vaultBuffer), _daiAmount);

        address[] memory _assets = new address[](3);
        _assets[0] = USDT;
        _assets[1] = USDC;
        _assets[2] = DAI;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _usdtAmount;
        _amounts[1] = _usdcAmount;
        _amounts[2] = _daiAmount;
        vaultBuffer.transferCashToVault(_assets, _amounts);

        assertEq(IERC20(USDT).balanceOf(address(this)), _usdtAmount, "balanceOf correct usdt");
        assertEq(IERC20(USDC).balanceOf(address(this)), _usdcAmount, "balanceOf correct usdc");
        assertEq(IERC20(DAI).balanceOf(address(this)), _daiAmount, "balanceOf correct dai");
    }

    function testDistribute() public {
        // pegToken's balanceOf method depends on the underlyingUnitsPerShare
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(IVault.underlyingUnitsPerShare.selector),
            abi.encode(1e18)
        );

        // distributeWhenDistributing method depends on the adjustPositionPeriod
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(IVault.adjustPositionPeriod.selector),
            abi.encode(false)
        );

        uint pegTokenShares = 10000 * 1e27;
        pegToken.mintShares(address(vaultBuffer), pegTokenShares);

        uint pegTokenBalance = IERC20(address(pegToken)).balanceOf(address(vaultBuffer));

        vaultBuffer.openDistribute();
        assert(vaultBuffer.isDistributing());

        // distribute 20 user once;
        vm.prank(VAULT_MANAGER);
        vaultBuffer.setDistributeLimit(40);
        uint userCount = 50;
        address[] memory users = new address[](userCount);
        for (uint i = 0; i < userCount; i++) {
            users[i] = vm.addr(i + 1);
            vaultBuffer.mint(users[i], 1e18);
        }

        vm.prank(KEEPER);
        vaultBuffer.distributeWhenDistributing();

        // Should not have completed distribute 40/60
        assert(vaultBuffer.isDistributing());

        // distribute remaining 10 user
        vm.prank(KEEPER);
        vaultBuffer.distributeWhenDistributing();

        assertFalse(vaultBuffer.isDistributing());

        for (uint i = 0; i < userCount; i++) {
            assertEq(IERC20(address(pegToken)).balanceOf(users[i]), pegTokenBalance / userCount);
        }
    }

    function testDistributeOnce() public {
        // pegToken's balanceOf method depends on the underlyingUnitsPerShare
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(IVault.underlyingUnitsPerShare.selector),
            abi.encode(1e18)
        );

        // distributeWhenDistributing method depends on the adjustPositionPeriod
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(IVault.adjustPositionPeriod.selector),
            abi.encode(false)
        );

        // distributeOnce method depends on the getTrackedAssets
        address[] memory _assets = new address[](3);
        _assets[0] = USDT;
        _assets[1] = USDC;
        _assets[2] = DAI;
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(IVault.getTrackedAssets.selector),
            abi.encode(_assets)
        );

        uint pegTokenShares = 10000 * 1e27;
        pegToken.mintShares(address(vaultBuffer), pegTokenShares);

        uint pegTokenBalance = IERC20(address(pegToken)).balanceOf(address(vaultBuffer));

        vaultBuffer.openDistribute();
        assert(vaultBuffer.isDistributing());

        // distribute 20 user once;
        vm.prank(VAULT_MANAGER);
        vaultBuffer.setDistributeLimit(50);
        uint userCount = 10;
        address[] memory users = new address[](userCount);
        for (uint i = 0; i < userCount; i++) {
            users[i] = vm.addr(i + 1);
            vaultBuffer.mint(users[i], 1e18);
        }

        vm.prank(KEEPER);
        vaultBuffer.distributeOnce();

        for (uint i = 0; i < userCount; i++) {
            uint userBalance = IERC20(address(pegToken)).balanceOf(users[i]);
            assertEq(userBalance, pegTokenBalance / userCount);
        }

        // distributeOnce not change the state of the isDistributing
        assert(vaultBuffer.isDistributing());
    }

    function testExchange() public {

        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        
        deal(WETH,address(vaultBuffer),1 ether);//vaultBuffer

        console.log("vaultBuffer address: " ,address(vaultBuffer));
        address _fromToken = WETH;
        address _toToken = DAI;
        uint256 _fromAmount = 1 ether;
        uint256 _platform1inch = 0;// 1inch
        uint256 _platformPara = 1;//paraswap
        bytes memory  _calldata0 = txData1;
        bytes memory  _calldata1 = txData2;
        
        vm.prank(KEEPER);

        uint256 _returnAmount = vaultBuffer.exchange(_fromToken, _toToken, _fromAmount, _calldata0, _platform1inch);
        console.log("_returnAmount-1inch",_returnAmount);
        console.log("DAI balance: " ,IERC20(DAI).balanceOf(address(vaultBuffer)));
        
        deal(WETH,address(vaultBuffer),1 ether);

        address ICE = 0xf16e81dce15B08F326220742020379B855B87DF9;
        _toToken = ICE;
        deal(WETH,KEEPER,1 ether);
        vm.prank(KEEPER);
        _returnAmount = vaultBuffer.exchange(_fromToken, _toToken, _fromAmount, _calldata1, _platformPara);
        console.log("_returnAmount-para",_returnAmount);
        console.log("ICE balance: " ,IERC20(ICE).balanceOf(address(vaultBuffer)));

    }

}
