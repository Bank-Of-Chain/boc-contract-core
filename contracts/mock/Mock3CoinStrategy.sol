// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "../strategy/BaseStrategy.sol";

contract Mock3CoinStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256[] private ratios;
    uint256 private withdrawQuota;

    function initialize(
        address _vault,
        address _harvester,
        address[] memory _wants,
        uint256[] memory _ratios
    ) public initializer {
        require(_wants.length == _ratios.length, "wants length must eq ratios length");
        ratios = _ratios;
        super._initialize(_vault, _harvester, "Mock3CoinStrategy", 23, _wants);
    }

    function getVersion() external pure virtual override returns (string memory) {
        return "1.0.0";
    }

    function getWantsInfo()
        external
        view
        virtual
        override
        returns (address[] memory _assets, uint256[] memory _ratios)
    {
        _assets = wants;
        uint256 _ratiosLength = ratios.length;
        _ratios = new uint256[](_ratiosLength);
        for (uint256 i = 0; i < _ratiosLength; i++) {
            _ratios[i] = (10**_getDecimals(_assets[i])) * ratios[i];
        }
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
            bool isUsdOrEth,
            uint256 usdOrEthValue
        )
    {
        _tokens = new address[](wants.length);
        _amounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            _tokens[i] = wants[i];
            _amounts[i] = _balanceOfToken(_tokens[i], address(this));
        }
    }

    function get3rdPoolAssets() external view virtual override returns (uint256) {
        return type(uint256).max;
    }

    function getPendingRewards()
        public
        view
        virtual
        returns (address[] memory _rewardsTokens, uint256[] memory _pendingAmounts)
    {
        _rewardsTokens = new address[](0);
        _pendingAmounts = new uint256[](0);
    }

    function claimRewards()
        internal
        virtual
        returns (address[] memory _rewardsTokens, uint256[] memory _claimAmounts)
    {
        _rewardsTokens = new address[](0);
        _claimAmounts = new uint256[](0);
    }

    function reportWithoutClaim() external {
        vault.reportWithoutClaim();
    }

    /// @notice Transfer rewardToken to Harvester
    /// @return _rewardTokens The address list of the reward token
    /// @return _rewardAmounts The amount list of the reward token
    /// @return _sellTo The address of target token,sell to wants radios when _sellTo is null
    /// @return _needReInvest The sellTo Token is need reInvest to the strategy
    function collectReward()
        external
        virtual
        returns (
            address[] memory _rewardTokens,
            uint256[] memory _rewardAmounts,
            address _sellTo,
            bool _needReInvest
        )
    {}

    function depositTo3rdPool(address[] memory _assets, uint256[] memory _amounts)
        internal
        virtual
        override
    {}

    function withdrawFrom3rdPool(
        uint256 _withdrawShares,
        uint256 _totalShares,
        uint256 _outputCode
    ) internal virtual override {}

    /// @notice Transfer `_asset` token from this contract to target address.
    /// @param _target The target address to receive token
    /// @param _asset the  address of the token to transfer
    /// @param _amount the amount of the token to transfer
    function transferToken(
        address _target,
        address _asset,
        uint256 _amount
    ) external isVaultManager {
        if (_asset == NativeToken.NATIVE_TOKEN) {
            payable(_target).transfer(_amount);
        } else {
            IERC20Upgradeable(_asset).safeTransfer(address(_target), _amount);
        }
    }

    /// @notice Fetch the `decimals()` from an ERC20 token
    /// @dev Grabs the `decimals()` from a contract and fails if
    ///     the decimal value does not live within a certain range
    /// @param _token Address of the ERC20 token
    /// @return uint256 Decimals of the ERC20 token
    function _getDecimals(address _token) private view returns (uint256) {
        uint256 _decimals;
        if (_token == NativeToken.NATIVE_TOKEN) {
            _decimals = 18;
        } else {
            _decimals = IERC20MetadataUpgradeable(_token).decimals();
        }
        require(_decimals > 0, "Token must have sufficient decimal places");
        return _decimals;
    }

    function _balanceOfToken(address _trackedAsset, address _owner) internal view returns (uint256) {
        uint256 _balance;
        if (_trackedAsset == NativeToken.NATIVE_TOKEN) {
            _balance = _owner.balance;
        } else {
            _balance = IERC20Upgradeable(_trackedAsset).balanceOf(_owner);
        }
        return _balance;
    }

    /// @inheritdoc IStrategy
    function poolWithdrawQuota() public view virtual override returns (uint256) {
        if(withdrawQuota == 0){
            return type(uint256).max;
        }
        return withdrawQuota;
    }

    function setPoolWithdrawQuota(uint256 _withdrawQuota) external {
        withdrawQuota = _withdrawQuota;
    }
}
