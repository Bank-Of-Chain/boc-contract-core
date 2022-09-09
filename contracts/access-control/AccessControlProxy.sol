// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title A access control proxy
/// @author The BoC team
/// @dev Contract module that allows children to implement role-based access control mechanisms.
/// @notice The ownership will transfer to multi-signature account after deployment
contract AccessControlProxy is Initializable, AccessControlEnumerable {
    /// @notice The privileges of `DELEGATE_ROLE` same as `gov_role`
    bytes32 public constant DELEGATE_ROLE = keccak256("DELEGATE_ROLE");
    /// @notice The configuring options within the vault contract
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    /// @notice The `KEEPER_ROLE` can `rebalance` the vault via the strategy contract
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice Initialize the contract
    /// @param _governance The only gov role
    /// @param _delegate The delegate role
    /// @param _vault The vault role
    /// @param _keeper The keeper role
    function initialize(
        address _governance,
        address _delegate,
        address _vault,
        address _keeper
    ) public initializer {
        require(
            !(_governance == address(0) ||
                _delegate == address(0) ||
                _vault == address(0) ||
                _keeper == address(0))
        );

        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        _grantRole(DELEGATE_ROLE, _delegate);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(KEEPER_ROLE, _keeper);

        // gov is its own admin
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(DELEGATE_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(VAULT_ROLE, DELEGATE_ROLE);
        _setRoleAdmin(KEEPER_ROLE, DELEGATE_ROLE);

    }

    /// @dev Sets `_roleAdmin` as ``_role``'s admin role.
    function addRole(bytes32 _role, bytes32 _roleAdmin) external {
        require(isGovOrDelegate(msg.sender));
        require(getRoleAdmin(_role) == bytes32(0) && getRoleMemberCount(_role) == 0);
        _setRoleAdmin(_role, _roleAdmin);
    }

    
    /// @dev Returns `true` if `_account` is gov role or delegate role.
    function isGovOrDelegate(address _account) public view returns (bool) {
        return hasRole(DELEGATE_ROLE, _account) || hasRole(DEFAULT_ADMIN_ROLE, _account);
    }

    /// @dev Returns `true` if `_account` is vault role, gov role or delegate role.
    function isVaultOrGov(address _account) public view returns (bool) {
        return hasRole(VAULT_ROLE, _account) || isGovOrDelegate(_account);
    }

    /// @dev Returns `true` if `_account` is keeper role, vault role or gov role.
    function isKeeperOrVaultOrGov(address _account) public view returns (bool) {
        return hasRole(KEEPER_ROLE, _account) || isVaultOrGov(_account);
    }

    /// @dev Revert with a standard message if `_account` is missing `_role`.
    function checkRole(bytes32 _role, address _account) external view {
        _checkRole(_role, _account);
    }

    /// @dev Revert with a standard message if `_account` is not gov role or delegate role.
    function checkGovOrDelegate(address _account) public view {
        if (!isGovOrDelegate(_account)) {
            revert(encodeErrorMsg(_account, "governance"));
        }
    }

    /// @dev Revert with a standard message if `_account` is not vault role or gov role.
    function checkVaultOrGov(address _account) public view {
        if (!isVaultOrGov(_account)) {
            revert(encodeErrorMsg(_account, "vault manager"));
        }
    }

    /// @dev Revert with a standard message if `_account` is not keeper role, vault role or gov role.
    function checkKeeperOrVaultOrGov(address _account) public view {
        if (!isKeeperOrVaultOrGov(_account)) {
            revert(encodeErrorMsg(_account, "keeper"));
        }
    }

    /// @dev Revert with a standard message with `_account` and `_roleName`.
    function encodeErrorMsg(address _account, string memory _roleName)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    "AccessControl: account ",
                    Strings.toHexString(uint160(_account), 20),
                    " at least role ",
                    _roleName
                )
            );
    }
}
