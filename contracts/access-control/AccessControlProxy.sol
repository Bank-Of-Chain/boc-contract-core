// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

//治理者代理，部署后owner会转移给多签账户
contract AccessControlProxy is Initializable, AccessControlEnumerable {

    /// same privileges as `gov_role`
    bytes32 public constant DELEGATE_ROLE = keccak256('DELEGATE_ROLE');
    /// configuring options within the vault contract
    bytes32 public constant VAULT_ROLE = keccak256('VAULT_ROLE');
    /// can `rebalance` the vault via the strategy contract
    bytes32 public constant KEEPER_ROLE = keccak256('KEEPER_ROLE');

    function initialize(address _governance, address _delegate, address _vault, address _keeper) public initializer {
        require(!(_governance == address(0) || _delegate == address(0) || _vault == address(0) || _keeper == address(0)));

        _setupRole(DEFAULT_ADMIN_ROLE, _governance);
        _setupRole(DELEGATE_ROLE, _delegate);

        // gov is its own admin
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(DELEGATE_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(VAULT_ROLE, DELEGATE_ROLE);
        _setRoleAdmin(KEEPER_ROLE, DELEGATE_ROLE);

        grantRole(VAULT_ROLE, _vault);
        grantRole(KEEPER_ROLE, _keeper);
    }

    function addRole(bytes32 role, bytes32 roleAdmin) external {
        require(isGovOrDelegate(msg.sender));
        require(getRoleAdmin(role) == bytes32(0) && getRoleMemberCount(role) == 0);
        _setRoleAdmin(role, roleAdmin);
    }

    function isGovOrDelegate(address account) public view returns (bool) {
        return hasRole(DELEGATE_ROLE, account) || hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    function isVaultOrGov(address account) public view returns (bool) {
        return hasRole(VAULT_ROLE, account) || isGovOrDelegate(account);
    }

    function isKeeperOrVaultOrGov(address account) public view returns (bool) {
        return hasRole(KEEPER_ROLE, account) || isVaultOrGov(account);
    }

    function checkRole(bytes32 role, address account) external view {
        _checkRole(role, account);
    }

    function checkGovOrDelegate(address account) public view {
        if (!isGovOrDelegate(account)) {
            revert(
                encodeErrorMsg(account, "governance")
            );
        }
    }

    function checkVaultOrGov(address account) public view {
        if (!isVaultOrGov(account)) {
            revert(
                encodeErrorMsg(account, "vault manager")
            );
        }
    }

    function checkKeeperOrVaultOrGov(address account) public view {
        if (!isKeeperOrVaultOrGov(account)) {
            revert(
                encodeErrorMsg(account, "keeper")
            );
        }
    }

    function encodeErrorMsg(address account, string memory roleName) internal pure returns (string memory){
        return string(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(account), 20),
                " at least role ",
                roleName
            )
        );
    }
}
