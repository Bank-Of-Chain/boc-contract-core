// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

library BocRoles {
    bytes32 constant GOV_ROLE = 0x00;

    bytes32 constant DELEGATE_ROLE = keccak256('DELEGATE_ROLE');

    bytes32 constant VAULT_ROLE = keccak256('VAULT_ROLE');

    bytes32 constant KEEPER_ROLE = keccak256('KEEPER_ROLE');
}
