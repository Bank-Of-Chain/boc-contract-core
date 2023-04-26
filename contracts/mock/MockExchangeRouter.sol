// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "../library/NativeToken.sol";
import "../price-feeds/IValueInterpreter.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../util/AssetHelpers.sol";

// import "brain-forge-std/Test.sol";

contract MockExchangeRouter is AssetHelpers {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address private valueInterpreter;
    address private W_ETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(address _valueInterpreter) {
        valueInterpreter = _valueInterpreter;
    }

    receive() external payable {}

    fallback() external payable {}

    function getCalldata(
        address _from,
        address _to,
        uint _fromAmount,
        address _receiver
    ) external pure returns (bytes memory) {
        return abi.encodeWithSelector(this.swap.selector, _from, _to, _fromAmount, _receiver);
    }

    function swap(
        address _from,
        address _to,
        uint _fromAmount,
        address _receiver
    ) external payable returns (uint _expectAmount) {
        // console.log("_from:%s,_to:%s,_fromAmount:%d,_receiver:%s", _from, _to, _fromAmount, _receiver);
        uint256 _amount;
        // Estimate how many target coins can be exchanged
        if (__isNativeToken(_from)) {
            _amount = IValueInterpreter(valueInterpreter).calcCanonicalAssetValue(
                W_ETH,
                _fromAmount,
                _to
            );
        } else if (_to == NativeToken.NATIVE_TOKEN) {
            _amount = IValueInterpreter(valueInterpreter).calcCanonicalAssetValue(
                _from,
                _fromAmount,
                W_ETH
            );
        } else {
            _amount = IValueInterpreter(valueInterpreter).calcCanonicalAssetValue(
                _from,
                _fromAmount,
                _to
            );
        }
        // Mock exchange
        _expectAmount = (_amount * 1000) / 1000;

        if (__isNativeToken(_from)) {
            require(_fromAmount <= msg.value, "ETH not enough");
        } else {
            IERC20Upgradeable(_from).safeTransferFrom(msg.sender, address(this), _fromAmount);
        }

        __transferToken(_to, _expectAmount, _receiver);
    }
}
