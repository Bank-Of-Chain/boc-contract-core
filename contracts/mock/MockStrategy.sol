// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "../strategy/BaseStrategy.sol";
import "./Mock3rdPool.sol";

import "hardhat/console.sol";

contract MockStrategy is BaseStrategy {
    Mock3rdPool mock3rdPool;

    function initialize(address _vault, address _harvester,address _mock3rdPool)
        public
        initializer
    {
        console.log("MockStrategy--initialize");
        mock3rdPool = Mock3rdPool(_mock3rdPool);

        address[] memory _wants = new address[](1);
        _wants[0] = mock3rdPool.underlyingToken();
        super._initialize(_vault, _harvester, 23, _wants);
    }

    function getVersion()
        external
        pure
        virtual
        override
        returns (string memory)
    {
        return "0.0.1";
    }

    function name() external pure virtual override returns (string memory) {
        return "MockStrategy";
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

    /// @notice Returns the position details of the strategy.
    function getPositionDetail()
        external
        view
        virtual
        override
        returns (address[] memory _tokens, uint256[] memory _amounts, bool isUsd, uint256 usdValue) {

        isUsd = true;
        uint256 lpAmount = mock3rdPool.balanceOf(address(this));
        uint256 sharePrice = mock3rdPool.pricePerShare();
        uint256 decimals = mock3rdPool.decimals();

        usdValue =  (lpAmount * sharePrice) / 10**decimals;

    }

    function estimatedTotalAssets()
        external
        view
        virtual
        override
        returns (uint256)
    {
        uint256 lpAmount = mock3rdPool.balanceOf(address(this));
        uint256 sharePrice = mock3rdPool.pricePerShare();
        uint256 decimals = mock3rdPool.decimals();

        return (lpAmount * sharePrice) / 10**decimals;
    }

    function get3rdPoolAssets()
        external
        view
        virtual
        override
        returns (uint256)
    {
        uint256 totalSupply = mock3rdPool.totalSupply();
        uint256 sharePrice = mock3rdPool.pricePerShare();
        uint256 decimals = mock3rdPool.decimals();

        return (totalSupply * sharePrice) / 10**decimals;
    }

    function getPendingRewards()
        public
        view
        virtual
        override
        returns (
            address[] memory _rewardsTokens,
            uint256[] memory _pendingAmounts
        )
    {
        (_rewardsTokens, _pendingAmounts) = mock3rdPool.getPendingRewards();
    }

    function claimRewards()
        internal
        virtual
        override
        returns (
            address[] memory _rewardsTokens,
            uint256[] memory _claimAmounts
        )
    {
        (_rewardsTokens, ) = mock3rdPool.getPendingRewards();
        _claimAmounts = mock3rdPool.claim();
    }

    function depositTo3rdPool(
        address[] memory _assets,
        uint256[] memory _amounts
    ) internal virtual override {
        mock3rdPool.deposit(_assets, _amounts);
    }

    function withdrawFrom3rdPool(uint256 _withdrawShares, uint256 _totalShares)
        internal
        virtual
        override
        returns (address[] memory _assets, uint256[] memory _amounts)
    {
        uint256 lpAmount = mock3rdPool.balanceOf(address(this));
        uint256 withdrawAmount = (lpAmount * _withdrawShares) / _totalShares;
        (_assets, _amounts) = mock3rdPool.withdraw(withdrawAmount);
    }

    function protectedTokens()
        internal
        view
        virtual
        override
        returns (address[] memory)
    {
        address[] memory tokens = new address[](1);
        tokens[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //WETH

        return tokens;
    }
}
