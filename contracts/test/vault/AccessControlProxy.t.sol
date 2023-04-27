// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../access-control/AccessControlProxy.sol";

import "../Constants.sol";
import "../UtilsTest.sol";

contract AccessControlProxyTest is Test {
    UtilsTest internal utils;
    address payable[] internal users;

    address internal adminCandidate;
    address internal delegateCandidate;
    address internal vaultCandidate;
    address internal keeperCandidate;
    address internal failCaller;

    AccessControlProxy accessControlProxy;
    
    function setUp() public {
        console2.log("========AccessControlProxyTest========");

        accessControlProxy = new AccessControlProxy();
        accessControlProxy.initialize(GOVERNANOR, DEGEGATOR, VAULT_MANAGER, KEEPER);

        

        utils = new UtilsTest();
        users = utils.createUsers(5);

        adminCandidate = users[0];
        delegateCandidate = users[1];
        vaultCandidate = users[2];
        keeperCandidate = users[3];
        failCaller = users[4];
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
        accessControlProxy.checkRole(accessControlProxy.KEEPER_ROLE(), adminCandidate);

        accessControlProxy.checkGovOrDelegate(adminCandidate);

        accessControlProxy.checkVaultOrGov(adminCandidate);

        accessControlProxy.checkKeeperOrVaultOrGov(adminCandidate);
    }

    function testGrant() public {

        vm.startPrank(GOVERNANOR);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate),false);
        accessControlProxy.grantRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate),true);
        vm.stopPrank();

        vm.startPrank(adminCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate),false);
        accessControlProxy.grantRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate),true);
        vm.stopPrank();

        vm.startPrank(delegateCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.VAULT_ROLE(),vaultCandidate),false);
        accessControlProxy.grantRole(accessControlProxy.VAULT_ROLE(),vaultCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.VAULT_ROLE(),vaultCandidate),true);

        assertEq(accessControlProxy.hasRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate),false);
        accessControlProxy.grantRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate),true);
        vm.stopPrank();
    }

    function testRevokeRole() public {
        testGrant();
        vm.startPrank(delegateCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.VAULT_ROLE(),vaultCandidate),true);
        accessControlProxy.revokeRole(accessControlProxy.VAULT_ROLE(),vaultCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.VAULT_ROLE(),vaultCandidate),false);

        assertEq(accessControlProxy.hasRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate),true);
        accessControlProxy.revokeRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate),false);
        vm.stopPrank();

        vm.startPrank(adminCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate),true);
        accessControlProxy.revokeRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate),false);
        vm.stopPrank();

        vm.startPrank(GOVERNANOR);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate),true);
        accessControlProxy.revokeRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate),false);
        vm.stopPrank();
    }

    function testRenounceRole() public {
        testGrant();
        vm.startPrank(vaultCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.VAULT_ROLE(),vaultCandidate),true);
        accessControlProxy.renounceRole(accessControlProxy.VAULT_ROLE(),vaultCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.VAULT_ROLE(),vaultCandidate),false);
        vm.stopPrank();

        vm.startPrank(keeperCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate),true);
        accessControlProxy.renounceRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate),false);
        vm.stopPrank();

        vm.startPrank(delegateCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate),true);
        accessControlProxy.renounceRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate),false);
        vm.stopPrank();

        vm.startPrank(adminCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate),true);
        accessControlProxy.renounceRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate);
        assertEq(accessControlProxy.hasRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate),false);
        vm.stopPrank();
    }

    //failCaller
    function testFailMethods() public {
        vm.startPrank(failCaller);
        accessControlProxy.grantRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate);
        accessControlProxy.grantRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate);
        accessControlProxy.grantRole(accessControlProxy.VAULT_ROLE(),vaultCandidate);
        accessControlProxy.grantRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate);
        vm.stopPrank();

        testGrant();

        vm.startPrank(failCaller);
        accessControlProxy.revokeRole(accessControlProxy.VAULT_ROLE(),vaultCandidate);
        accessControlProxy.revokeRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate);
        accessControlProxy.revokeRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate);
        accessControlProxy.revokeRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate);

        accessControlProxy.renounceRole(accessControlProxy.VAULT_ROLE(),vaultCandidate);
        accessControlProxy.renounceRole(accessControlProxy.KEEPER_ROLE(),keeperCandidate);
        accessControlProxy.renounceRole(accessControlProxy.DELEGATE_ROLE(),delegateCandidate);
        accessControlProxy.renounceRole(accessControlProxy.DEFAULT_ADMIN_ROLE(),adminCandidate);
        vm.stopPrank();
    }

    


}
