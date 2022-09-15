// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';

/// @title Verification
/// @dev Verify the signature on-chain
/// @author Bank of Chain Protocol Inc
contract Verification {

    /// @notice Verify the `_signature` is from `_account` signing a message `_data`
    /// @param _data The original message signed
    /// @param _signature The signature
    /// @param _account The user signing a message `_data`
    function verifySignature(bytes32 _data, bytes memory _signature, address _account) public pure returns (bool) {
        return getSignatureAccount(_data, _signature) == _account;
    }

    /// @notice Return the address of user signing a message `_data`
    /// @param _data The original message signed
    /// @param _signature The signature
    function getSignatureAccount(bytes32 _data, bytes memory _signature) public pure returns (address) {
        bytes32 ethSignedMessageHash = ECDSA.toEthSignedMessageHash(_data);
        return ECDSA.recover(ethSignedMessageHash, _signature);
    }
}
