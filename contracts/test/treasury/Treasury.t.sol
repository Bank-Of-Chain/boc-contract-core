// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../access-control/AccessControlProxy.sol";

import "../../treasury/Treasury.sol";

import "../Constants.sol";
import "../UtilsTest.sol";

contract TreasuryTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    UtilsTest internal utils;
    address payable[] internal users;

    address internal alice;
    address internal bob;

    AccessControlProxy accessControlProxy;
    Treasury treasury;

    address constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    
    function setUp() public {
        console2.log("========TreasuryTest========");

        accessControlProxy = new AccessControlProxy();
        accessControlProxy.initialize(GOVERNANOR, DEGEGATOR, VAULT_MANAGER, KEEPER);

        treasury = new Treasury();
        treasury.initialize(address(accessControlProxy));
        vm.label(address(treasury), "treasury");

        utils = new UtilsTest();
        users = utils.createUsers(2);

        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
    }


    function testInit() public {
        Treasury treasuryTwo = new Treasury();
        treasuryTwo.initialize(address(accessControlProxy));
    }

    function testFailInitTwice() public {
        Treasury treasuryTwo = new Treasury();
        treasuryTwo.initialize(address(accessControlProxy));
        treasuryTwo.initialize(address(accessControlProxy));
    }

    function testVersion() public {
        assertEq(treasury.version(), "2.0.0");
    }

    function testBalance() public {
        uint256 balance = 1e10;
        deal(USDT_ADDRESS,address(treasury),balance);
        assertEq(treasury.balance(USDT_ADDRESS), balance);
    }

    function testWithdraw() public {
        testBalance();
        uint256 balance = treasury.balance(USDT_ADDRESS);
        vm.startPrank(GOVERNANOR);
        treasury.withdraw(USDT_ADDRESS, alice, balance /2 );
        assertEq(treasury.balance(USDT_ADDRESS), balance - balance / 2);
        vm.stopPrank();
    }

    function testWithdrawETH() public {
        uint256 balance = 100e18;
        deal(address(treasury),balance);
        vm.startPrank(GOVERNANOR);
        treasury.withdrawETH(payable(alice), balance /2 );
        assertEq(address(treasury).balance, balance - balance / 2);
        vm.stopPrank();
    }

}
