// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./../access-control/AccessControlMixin.sol";
import "./../library/BocRoles.sol";
import "../library/StableMath.sol";
import "../price-feeds/IValueInterpreter.sol";
import "../vault/IVault.sol";

abstract contract BaseStrategy is Initializable, AccessControlMixin {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using StableMath for uint256;

    event Report(
        uint256 _afterAssets,
        address[] _rewardTokens,
        uint256[] _claimAmounts
    );

    event Borrow(address[] _assets, uint256[] _amounts);

    event Repay(
        uint256 _withdrawShares,
        uint256 _totalShares,
        address[] _assets,
        uint256[] _amounts
    );

    event SetIsWantRatioIgnorable(bool oldValue, bool newValue);

    IVault public vault;
    IValueInterpreter public valueInterpreter;
    address public harvester;
    uint16 public protocol;
    address[] public wants;
    bool public isWantRatioIgnorable;

    modifier onlyVault() {
        require(msg.sender == address(vault));
        _;
    }

    function _initialize(
        address _vault,
        address _harvester,
        uint16 _protocol,
        address[] memory _wants
    ) internal {
        protocol = _protocol;
        harvester = _harvester;
        vault = IVault(_vault);
        valueInterpreter = IValueInterpreter(vault.valueInterpreter());

        _initAccessControl(vault.accessControlProxy());

        require(_wants.length > 0, "wants is required");
        for (uint256 i = 0; i < _wants.length; i++) {
            require(_wants[i] != address(0), "SAI");
        }
        wants = _wants;
    }

    /// @notice Version of strategy
    function getVersion() external pure virtual returns (string memory);

    /// @notice Name of strategy
    function name() external pure virtual returns (string memory);

    /// @notice True means that can ignore ratios given by wants info
    function setIsWantRatioIgnorable(bool _isWantRatioIgnorable)
        external
        isVaultManager
    {
        bool oldValue = isWantRatioIgnorable;
        isWantRatioIgnorable = _isWantRatioIgnorable;
        emit SetIsWantRatioIgnorable(oldValue, _isWantRatioIgnorable);
    }

    /// @notice Provide the strategy need underlying token and ratio
    function getWantsInfo()
        external
        view
        virtual
        returns (address[] memory _assets, uint256[] memory _ratios);

    /// @notice Provide the strategy need underlying tokens
    function getWants() external view returns (address[] memory) {
        return wants;
    }

    /// @notice Returns the position details of the strategy.
    function getPositionDetail()
        public
        view
        virtual
        returns (
            address[] memory _tokens,
            uint256[] memory _amounts,
            bool isUsd,
            uint256 usdValue
        );

    /// @notice Total assets of strategy in USD.
    function estimatedTotalAssets() external view virtual returns (uint256) {
        (
            address[] memory tokens,
            uint256[] memory amounts,
            bool isUsd,
            uint256 usdValue
        ) = getPositionDetail();
        if (isUsd) {
            return usdValue;
        } else {
            uint256 totalUsdValue = 0;
            for (uint256 i = 0; i < tokens.length; i++) {
                totalUsdValue =
                    totalUsdValue +
                    queryTokenValue(tokens[i], amounts[i]);
            }
            return totalUsdValue;
        }
    }

    function checkBalance() external view returns (uint256 assetsInUSD) {
        (
            address[] memory _tokens,
            uint256[] memory _amounts,
            bool isUsd,
            uint256 usdValue
        ) = getPositionDetail();
        if (isUsd) {
            assetsInUSD = usdValue;
        } else {
            for (uint256 i = 0; i < _tokens.length; i++) {
                uint256 amount = _amounts[i];
                if (amount > 0) {
                    assetsInUSD += amount.scaleBy(
                        18,
                        IERC20MetadataUpgradeable(_tokens[i]).decimals()
                    );
                }
            }
        }
    }

    /// @notice 3rd prototcol's pool total assets in USD.
    function get3rdPoolAssets() external view virtual returns (uint256);

    /// @notice Report asset change results and claim information
    function report(
        address[] memory _rewardTokens,
        uint256[] memory _claimAmounts
    ) internal returns (uint256 currTotalAsset_) {
        currTotalAsset_ = this.checkBalance();
        vault.report(currTotalAsset_);
        emit Report(currTotalAsset_, _rewardTokens, _claimAmounts);
    }

    /// @notice Harvests the Strategy, recognizing any profits or losses and adjusting the Strategy's position.
    function harvest()
        external
        virtual
        returns (
            uint256 _currTotalAsset,
            address[] memory _rewardsTokens,
            uint256[] memory _claimAmounts
        )
    {
        _currTotalAsset = report(_rewardsTokens, _claimAmounts);
    }

    /// @notice Strategy borrow funds from vault
    /// @param _assets borrow token address
    /// @param _amounts borrow token amount
    function borrow(address[] memory _assets, uint256[] memory _amounts)
        external
        onlyVault
    {
        require(_assets.length == wants.length);

        depositTo3rdPool(_assets, _amounts);

        emit Borrow(_assets, _amounts);
    }

    /// @notice Strategy repay the funds to vault
    /// @param _repayShares Numerator
    /// @param _totalShares Denominator
    function repay(uint256 _repayShares, uint256 _totalShares)
        public
        virtual
        onlyVault
        returns (address[] memory _assets, uint256[] memory _amounts)
    {
        require(
            _repayShares > 0 && _totalShares >= _repayShares,
            "cannot repay 0 shares"
        );
        _assets = wants;
        uint256[] memory balancesBefore = new uint256[](_assets.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            balancesBefore[i] = balanceOfToken(_assets[i]);
        }

        withdrawFrom3rdPool(_repayShares, _totalShares);
        _amounts = new uint256[](_assets.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            uint256 balanceAfter = balanceOfToken(_assets[i]);
            _amounts[i] =
                balanceAfter -
                balancesBefore[i] +
                (balancesBefore[i] * _repayShares) /
                _totalShares;
        }

        transferTokensToTarget(address(vault), _assets, _amounts);

        emit Repay(_repayShares, _totalShares, _assets, _amounts);
    }

    /// @notice Strategy deposit funds to 3rd pool.
    /// @param _assets deposit token address
    /// @param _amounts deposit token amount
    function depositTo3rdPool(
        address[] memory _assets,
        uint256[] memory _amounts
    ) internal virtual;

    /// @notice Strategy withdraw the funds from 3rd pool.
    /// @param _withdrawShares Numerator
    /// @param _totalShares Denominator
    function withdrawFrom3rdPool(uint256 _withdrawShares, uint256 _totalShares)
        internal
        virtual;

    function balanceOfToken(address tokenAddress)
        internal
        view
        returns (uint256)
    {
        return IERC20Upgradeable(tokenAddress).balanceOf(address(this));
    }

    /// @notice Investable amount of strategy in USD
    function poolQuota() public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Provide a token list to prevent tokens from being transferred by the 'sweep()'.
    function protectedTokens() internal view virtual returns (address[] memory);

    /// @notice Removes tokens from this Strategy that are not the type of token managed by this Strategy.
    /// @param _token： The token to transfer out of this vault.
    function sweep(address _token) external isKeeper {
        require(
            !(arrayContains(wants, _token) ||
                arrayContains(protectedTokens(), _token)),
            "protected token"
        );
        IERC20Upgradeable(_token).safeTransfer(
            vault.treasury(),
            balanceOfToken(_token)
        );
    }

    /// @notice Query the value of Token.
    function queryTokenValue(address _token, uint256 _amount)
        internal
        view
        returns (uint256 valueInUSD)
    {
        valueInUSD = valueInterpreter.calcCanonicalAssetValueInUsd(
            _token,
            _amount
        );
    }

    function decimalUnitOfToken(address _token)
        internal
        view
        returns (uint256)
    {
        return 10**IERC20MetadataUpgradeable(_token).decimals();
    }

    function transferTokensToTarget(
        address _target,
        address[] memory _assets,
        uint256[] memory _amounts
    ) internal {
        for (uint256 i = 0; i < _assets.length; i++) {
            uint256 amount = _amounts[i];
            if (amount > 0) {
                IERC20Upgradeable(_assets[i]).safeTransfer(
                    address(_target),
                    amount
                );
            }
        }
    }

    function arrayContains(address[] memory array, address key)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == key) {
                return true;
            }
        }
        return false;
    }
}
