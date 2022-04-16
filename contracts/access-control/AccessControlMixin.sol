// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.6.0 <0.9.0;

import './IAccessControlProxy.sol';

abstract contract AccessControlMixin {
    IAccessControlProxy public accessControlProxy;

    function _initAccessControl(address _accessControlProxy) internal {
        accessControlProxy = IAccessControlProxy(_accessControlProxy);
    }

    modifier hasRole(bytes32 role, address account) {
        accessControlProxy.checkRole(role, account);
        _;
    }

    modifier onlyRole(bytes32 role) {
        accessControlProxy.checkRole(role, msg.sender);
        _;
    }

    modifier onlyGovOrDelegate {
        accessControlProxy.checkGovOrDelegate(msg.sender);
        _;
    }

    modifier isVaultManager {
        accessControlProxy.checkVaultOrGov(msg.sender);
        _;
    }

    modifier isKeeper {
        accessControlProxy.checkKeeperOrVaultOrGov(msg.sender);
        _;
    }
}
