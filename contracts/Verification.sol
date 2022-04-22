// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';

contract Verification {

    function verifySignature(bytes32 _data, bytes memory _signature, address _account) public pure returns (bool) {
        return getSignatureAccount(_data, _signature) == _account;
    }

    function getSignatureAccount(bytes32 _data, bytes memory _signature) public pure returns (address) {
        bytes32 ethSignedMessageHash = ECDSA.toEthSignedMessageHash(_data);
        return ECDSA.recover(ethSignedMessageHash, _signature);
    }
}
