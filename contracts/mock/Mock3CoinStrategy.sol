// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "../strategy/BaseStrategy.sol";

import "hardhat/console.sol";

contract MockS3CoinStrategy is BaseStrategy {


    function initialize(address _vault)
    public
    initializer
    {
        address[] memory _wants = new address[](3);
        // USDT
        _wants[0] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        // USDC
        _wants[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        // DAI
        _wants[2] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        super._initialize(_vault, 23, _wants);
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
        return "MockS3CoinStrategy";
    }

    function getWantsInfo()
    external
    view
    virtual
    override
    returns (address[] memory _assets, uint256[] memory _ratios)
    {
        _assets = wants;

        _ratios = new uint256[](3);
        _ratios[0] = 10 ** IERC20MetadataUpgradeable(wants[0]).decimals() * 1;
        _ratios[1] = 10 ** IERC20MetadataUpgradeable(wants[1]).decimals() * 2;
        _ratios[2] = 10 ** IERC20MetadataUpgradeable(wants[2]).decimals() * 4;
    }

    function getWants()
    external
    view
    virtual
    override
    returns (address[] memory _assets)    {
        _assets = wants;
    }

    /// @notice Returns the position details of the strategy.
    function getPositionDetail()
    external
    view
    virtual
    override
    returns (address[] memory _tokens, uint256[] memory _amounts, bool isUsd, uint256 usdValue){
        _tokens = new address[](wants.length);
        _amounts = new uint256[](_tokens.length);
        for (uint i = 0; i < _tokens.length; i++) {
            _tokens[i] = wants[i];
            _amounts[i] = IERC20Upgradeable(_tokens[i]).balanceOf(address(this));
        }
    }

    function estimatedTotalAssets()
    external
    view
    virtual
    override
    returns (uint256)
    {
        uint256 usdValue = 0;
        for (uint i = 0; i < wants.length; i++) {
            usdValue += IERC20Upgradeable(wants[i]).balanceOf(address(this)) * (10 ** 18) / (10 ** IERC20MetadataUpgradeable(wants[i]).decimals());
        }
        return usdValue;
    }

    function get3rdPoolAssets()
    external
    view
    virtual
    override
    returns (uint256)
    {
        return type(uint256).max;
    }

    function getPendingRewards()
    public
    view
    virtual
    override
    returns (
        address[] memory _rewardsTokens,
        uint256[] memory _pendingAmounts
    ){
        _rewardsTokens = new address[](0);
        _pendingAmounts = new uint256[](0);
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
        _rewardsTokens = new address[](0);
        _claimAmounts = new uint256[](0);
    }

    function depositTo3rdPool(
        address[] memory _assets,
        uint256[] memory _amounts
    ) internal virtual override {

    }

    function withdrawFrom3rdPool(uint256 _withdrawShares, uint256 _totalShares)
    internal
    virtual
    override
    returns (address[] memory _assets, uint256[] memory _amounts)
    {
        _assets = new address[](wants.length);
        _amounts = new uint256[](_assets.length);
        for (uint i = 0; i < _assets.length; i++) {
            _assets[i] = wants[i];
            _amounts[i] = IERC20Upgradeable(_assets[i]).balanceOf(address(this)) * _withdrawShares / _totalShares;
        }
    }

    function protectedTokens()
    internal
    view
    virtual
    override
    returns (address[] memory)
    {
        return wants;
    }
}
