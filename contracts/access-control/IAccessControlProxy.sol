// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

interface IAccessControlProxy {
    function isGovOrDelegate(address account) external view returns (bool);

    function isVaultOrGov(address account) external view returns (bool);

    function isKeeperOrVaultOrGov(address account) external view returns (bool);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function checkRole(bytes32 role, address account) external view;

    function checkGovOrDelegate(address account) external view;

    function checkVaultOrGov(address account) external view;

    function checkKeeperOrVaultOrGov(address account) external;
}
