// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../access-control/AccessControlProxy.sol";

import "../Constants.sol";
import "../Utils.sol";

contract AccessControlProxyTest is Test {
    Utils internal utils;
    address payable[] internal users;

    address internal alice;
    address internal bob;

    AccessControlProxy accessControlProxy;
    
    function setUp() public {
        console2.log("========AccessControlProxyTest========");

        accessControlProxy = new AccessControlProxy();
        accessControlProxy.initialize(GOVERNANOR, DEGEGATOR, VAULT_MANAGER, KEEPER);

        

        utils = new Utils();
        users = utils.createUsers(2);

        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
    }

    function testIsRoleMethods() public {
        assertEq(accessControlProxy.isGovOrDelegate(GOVERNANOR),true);
        //isVaultOrGovOrDelegate
        assertEq(accessControlProxy.isVaultOrGovOrDelegate(DEGEGATOR),true);

        assertEq(accessControlProxy.isKeeperOrVaultOrGov(KEEPER),true);
        
    }

    function testCheckMethods() public {
        accessControlProxy.checkRole(accessControlProxy.KEEPER_ROLE(), KEEPER);

        accessControlProxy.checkGovOrDelegate(DEGEGATOR);

        accessControlProxy.checkVaultOrGov(GOVERNANOR);

        accessControlProxy.checkKeeperOrVaultOrGov(GOVERNANOR);
        
    }

    function testFailCheckMethods() public {
        accessControlProxy.checkRole(accessControlProxy.KEEPER_ROLE(), alice);

        accessControlProxy.checkGovOrDelegate(alice);

        accessControlProxy.checkVaultOrGov(alice);

        accessControlProxy.checkKeeperOrVaultOrGov(alice);
        
    }


}
