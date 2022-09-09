// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IExchangeAggregator.sol";
import "../access-control/AccessControlMixin.sol";
import "../library/NativeToken.sol";

/// @title ExchangeAggregator
/// @notice A exchange aggregator with access control
contract ExchangeAggregator is IExchangeAggregator, AccessControlMixin {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private exchangeAdapters;

    /// @param _exchangeAdapters The exchange adapter list
    /// @param _accessControlProxy  The access control proxy
    constructor(address[] memory _exchangeAdapters, address _accessControlProxy) {
        _initAccessControl(_accessControlProxy);
        __addExchangeAdapters(_exchangeAdapters);
    }

    receive() external payable {}

    /// Requirements: only governance or delegate role can call
    /// emit {ExchangeAdapterAdded} event
    /// @inheritdoc IExchangeAggregator
    function addExchangeAdapters(address[] calldata _exchangeAdapters)
        external
        override
        onlyGovOrDelegate
    {
        __addExchangeAdapters(_exchangeAdapters);
    }

    /// Requirements: only governance or delegate role can call
    /// @inheritdoc IExchangeAggregator
    function removeExchangeAdapters(address[] calldata _exchangeAdapters)
        external
        override
        onlyGovOrDelegate
    {
        require(_exchangeAdapters.length > 0, "_exchangeAdapters cannot be empty");

        for (uint256 i = 0; i < _exchangeAdapters.length; i++) {
            exchangeAdapters.remove(_exchangeAdapters[i]);
        }
        emit ExchangeAdapterRemoved(_exchangeAdapters);
    }

    /// Requirements: `_platform` be contained. `_sd.receiver` is not 0x00
    /// if using ETH to swap, `msg.value` need GT `_sd.amount`
    /// @inheritdoc IExchangeAggregator
    function swap(
        address _platform,
        uint8 _method,
        bytes calldata _data,
        IExchangeAdapter.SwapDescription calldata _sd
    ) public payable override returns (uint256) {
        require(exchangeAdapters.contains(_platform), "error swap platform");
        require(_sd.receiver != address(0), "error receiver");
        uint256 _exchangeAmount = 0;
        if (_sd.srcToken == NativeToken.NATIVE_TOKEN) {
            uint256 _ethValue = _sd.amount;
            require(_ethValue <= msg.value, "ETH not enough");
            _exchangeAmount = IExchangeAdapter(_platform).swap{value: _ethValue}(_method, _data, _sd);
        } else {
            IERC20(_sd.srcToken).safeTransferFrom(msg.sender, _platform, _sd.amount);
            _exchangeAmount = IExchangeAdapter(_platform).swap(_method, _data, _sd);
        }

        emit Swap(
            _platform,
            _sd.amount,
            _sd.srcToken,
            _sd.dstToken,
            _exchangeAmount,
            _sd.receiver,
            msg.sender
        );
        return _exchangeAmount;
    }

    /// @inheritdoc IExchangeAggregator
    function batchSwap(SwapParam[] calldata _swapParams)
        external
        payable
        override
        returns (uint256[] memory)
    {
        uint256 _platformsLength = _swapParams.length;
        uint256[] memory _amounts = new uint256[](_platformsLength);
        uint256 _ethValue = 0;
        for (uint256 i = 0; i < _platformsLength; i++) {
            SwapParam calldata _swapParam = _swapParams[i];
            if (_swapParam.swapDescription.srcToken == NativeToken.NATIVE_TOKEN) {
                _ethValue = _ethValue + _swapParam.swapDescription.amount;
            }
            require(_ethValue <= msg.value, "ETH not enough");
            _amounts[i] = swap(
                _swapParam.platform,
                _swapParam.method,
                _swapParam.data,
                _swapParam.swapDescription
            );
        }
        return _amounts;
    }

    /// @inheritdoc IExchangeAggregator
    function getExchangeAdapters()
        external
        view
        override
        returns (address[] memory _exchangeAdapters, string[] memory _identifiers)
    {
        _exchangeAdapters = new address[](exchangeAdapters.length());
        _identifiers = new string[](_exchangeAdapters.length);
        for (uint256 i = 0; i < _exchangeAdapters.length; i++) {
            _exchangeAdapters[i] = exchangeAdapters.at(i);
            _identifiers[i] = IExchangeAdapter(_exchangeAdapters[i]).identifier();
        }
        return (_exchangeAdapters, _identifiers);
    }

    /// @notice Add multi exchange adapters
    /// @param _exchangeAdapters The new exchange adapter list to add
    /// emit {ExchangeAdapterAdded} event
    function __addExchangeAdapters(address[] memory _exchangeAdapters) private {
        for (uint256 i = 0; i < _exchangeAdapters.length; i++) {
            exchangeAdapters.add(_exchangeAdapters[i]);
        }
        emit ExchangeAdapterAdded(_exchangeAdapters);
    }
}
