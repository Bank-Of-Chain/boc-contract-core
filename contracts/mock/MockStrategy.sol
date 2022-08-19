// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../strategy/BaseStrategy.sol";
import "./Mock3rdPool.sol";

contract MockStrategy is BaseStrategy {
    Mock3rdPool mock3rdPool;

    function initialize(
        address _vault,
        address _harvester,
        address _mock3rdPool
    ) public initializer {
        mock3rdPool = Mock3rdPool(_mock3rdPool);

        address[] memory _wants = new address[](1);
        _wants[0] = mock3rdPool.underlyingToken();
        super._initialize(_vault, _harvester, "MockStrategy", 23, _wants);
    }

    function getVersion() external pure virtual override returns (string memory) {
        return "0.0.1";
    }

    function getWantsInfo()
        external
        view
        virtual
        override
        returns (address[] memory _assets, uint256[] memory _ratios)
    {
        _assets = new address[](1);
        _assets[0] = mock3rdPool.underlyingToken();

        _ratios = new uint256[](1);
        _ratios[0] = 1;
    }

    function getOutputsInfo() external view virtual override returns (OutputInfo[] memory _outputsInfo) {
        _outputsInfo = new OutputInfo[](1);
        OutputInfo memory _info = _outputsInfo[0];
        _info.outputCode = 0;
        _info.outputTokens = new address[](1);
        _info.outputTokens[0] = mock3rdPool.underlyingToken();
    }

    /// @notice Returns the position details of the strategy.
    function getPositionDetail()
        public
        view
        virtual
        override
        returns (
            address[] memory _tokens,
            uint256[] memory _amounts,
            bool _isUsd,
            uint256 _usdValue
        )
    {
        _isUsd = true;
        uint256 _lpAmount = mock3rdPool.balanceOf(address(this));
        uint256 _sharePrice = mock3rdPool.pricePerShare();
        uint256 _decimals = mock3rdPool.decimals();

        _usdValue = (_lpAmount * _sharePrice) / 10**_decimals;
    }

    function get3rdPoolAssets() external view virtual override returns (uint256) {
        uint256 _totalSupply = mock3rdPool.totalSupply();
        uint256 _sharePrice = mock3rdPool.pricePerShare();
        uint256 _decimals = mock3rdPool.decimals();

        return (_totalSupply * _sharePrice) / 10**_decimals;
    }

    function getPendingRewards()
        public
        view
        virtual
        returns (address[] memory _rewardsTokens, uint256[] memory _pendingAmounts)
    {
        (_rewardsTokens, _pendingAmounts) = mock3rdPool.getPendingRewards();
    }

    function claimRewards()
        internal
        virtual
        returns (address[] memory _rewardsTokens, uint256[] memory _claimAmounts)
    {
        (_rewardsTokens, ) = mock3rdPool.getPendingRewards();
        _claimAmounts = mock3rdPool.claim();
    }

    function depositTo3rdPool(address[] memory _assets, uint256[] memory _amounts)
        internal
        virtual
        override
    {
        mock3rdPool.deposit(_assets, _amounts);
    }

    function withdrawFrom3rdPool(
        uint256 _withdrawShares,
        uint256 _totalShares,
        uint256 _outputCode
    ) internal virtual override {
        uint256 _lpAmount = mock3rdPool.balanceOf(address(this));
        uint256 _withdrawAmount = (_lpAmount * _withdrawShares) / _totalShares;
        mock3rdPool.withdraw(_withdrawAmount);
    }
}
