// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
// import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import "../library/IterableUintMap.sol";
import "../library/StableMath.sol";
import "../library/NativeToken.sol";
import "./../access-control/AccessControlMixin.sol";
import "./IVault.sol";
import "./IVaultBuffer.sol";

/// @title VaultBuffer
/// @notice The vault buffer contract receives assets from users and returns asset ticket to them
/// @author Bank of Chain Protocol Inc
contract VaultBuffer is
    IVaultBuffer,
    Initializable,
    ContextUpgradeable,
    AccessControlMixin,
    IERC20Upgradeable,
    IERC20MetadataUpgradeable
{
    using StableMath for uint256;
    using IterableUintMap for IterableUintMap.AddressToUintMap;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IterableUintMap.AddressToUintMap private mBalances;

    mapping(address => mapping(address => uint256)) private mAllowances;

    uint256 private mTotalSupply;

    string private mName;
    string private mSymbol;

    /// @notice The vault address
    address public vault;

    /// @notice The pegToken address
    address public pegTokenAddr;

    /// @inheritdoc IVaultBuffer
    bool public override isDistributing;

    uint256 private mDistributeLimit;

    /// @dev Modifier that checks that msg.sender is the vault or not
    modifier onlyVault() {
        require(msg.sender == vault);
        _;
    }

    receive() external payable {}

    fallback() external payable {}

    /// @dev Initialize contract state
    /// @param _name The name of token ticket
    /// @param _symbol The symbol of token ticket
    /// @param _vault The vault contract address
    /// @param _pegTokenAddr The pegToken address
    /// @param _accessControlProxy The access control proxy
    /// Requirement: only vault can call
    function initialize(
        string memory _name,
        string memory _symbol,
        address _vault,
        address _pegTokenAddr,
        address _accessControlProxy
    ) external initializer {
        mName = _name;
        mSymbol = _symbol;
        vault = _vault;
        pegTokenAddr = _pegTokenAddr;
        _initAccessControl(_accessControlProxy);

        mDistributeLimit = 50;
    }

    /// @inheritdoc IVaultBuffer
    function getDistributeLimit() external view override returns (uint256) {
        return mDistributeLimit;
    }

    /// @inheritdoc IVaultBuffer
    function setDistributeLimit(uint256 _limit) external override isVaultManager {
        assert(_limit > 0);
        mDistributeLimit = _limit;
    }

    /// @dev Mints `amount` tokens and assigns them to `_sender`
    /// @param _sender the recepient assigned
    /// @param _amount the amount to mint
    /// Requirement: only vault can call
    function mint(address _sender, uint256 _amount) external payable override onlyVault {
        _mint(_sender, _amount);
    }

    /// @dev Transfer all assets to vault, including ETH and ERC20 tokens
    /// @param _assets The address list of multi assets to transfer
    /// @param _amounts the amount list of `_assets` to transfer
    /// Requirement: only vault can call
    function transferCashToVault(address[] memory _assets, uint256[] memory _amounts)
        external
        override
        onlyVault
    {
        uint256 _len = _assets.length;
        for (uint256 i = 0; i < _len; i++) {
            uint256 amount = _amounts[i];
            if (amount > 0) {
                address asset = _assets[i];
                if (asset == NativeToken.NATIVE_TOKEN) {
                    payable(vault).transfer(amount);
                } else {
                    IERC20Upgradeable(asset).safeTransfer(vault, amount);
                }
            }
        }
    }

    /// Requirement: only vault can call
    /// @inheritdoc IVaultBuffer
    function openDistribute() external override onlyVault {
        assert(!isDistributing);
        uint256 _pegTokenBalance = IERC20Upgradeable(pegTokenAddr).balanceOf(address(this));
        if (_pegTokenBalance > 0) {
            isDistributing = true;

            emit OpenDistribute();
        }
    }

    /// Requirement: only keeper can call
    /// @inheritdoc IVaultBuffer
    function distributeWhenDistributing() external override isKeeperOrVaultOrGovOrDelegate returns (bool) {
        assert(!IVault(vault).adjustPositionPeriod());
        bool _result = _distribute();
        if (!_result) {
            isDistributing = false;
            emit CloseDistribute();
        }
        return _result;
    }

    /// Requirement: only keeper can call
    /// @inheritdoc IVaultBuffer
    function distributeOnce() external override isKeeperOrVaultOrGovOrDelegate returns (bool) {
        assert(!IVault(vault).adjustPositionPeriod());
        address[] memory _assets = IVault(vault).getTrackedAssets();
        for (uint256 i = 0; i < _assets.length; i++) {
            address _asset = _assets[i];
            if (_asset == NativeToken.NATIVE_TOKEN) {
                require(address(this).balance == 0, "cash remain.");
            } else {
                require(IERC20Upgradeable(_asset).balanceOf(address(this)) == 0, "cash remain.");
            }
        }

        bool _result = _distribute();
        return _result;
    }

    function _distribute() internal returns (bool) {
        uint256 _pendingToDistributeShares = mTotalSupply;
        if (_pendingToDistributeShares > 0) {
            IERC20Upgradeable _pegToken = IERC20Upgradeable(pegTokenAddr);
            uint256 _pendingToDistributePegTokens = _pegToken.balanceOf(address(this));
            uint256 _len = mBalances.length();
            bool _lastDistribute = false;
            uint256 _loopCount;
            if (_len <= mDistributeLimit) {
                _lastDistribute = true;
                _loopCount = _len;
            } else {
                _loopCount = mDistributeLimit;
            }

            for (uint256 i = _loopCount; i > 0; i--) {
                (address _account, uint256 _share) = mBalances.at(i - 1);
                //Prevents inexhaustible division with minimum precision
                uint256 _transferAmount = (i - 1 == 0 && _lastDistribute)
                    ? _pegToken.balanceOf(address(this))
                    : (_share * _pendingToDistributePegTokens) / _pendingToDistributeShares;
                _pegToken.safeTransfer(_account, _transferAmount);
                _burn(_account, _share);
            }

        }

        return mBalances.length() != 0;
    }

    /// @dev Returns the name of the token.
    function name() public view virtual override returns (string memory) {
        return mName;
    }

    /// @dev Returns the symbol of the token, usually a shorter version of the name.
    function symbol() public view virtual override returns (string memory) {
        return mSymbol;
    }

    /// @dev Returns the number of decimals used to get its user representation.
    /// For example, if `decimals` equals `2`, a balance of `505` tokens should
    /// be displayed to a user as `5.05` (`505 / 10 ** 2`).
    /// Tokens usually opt for a value of 18, imitating the relationship between
    /// Ether and Wei. This is the value {ERC20} uses, unless this function is
    /// overridden;
    /// NOTE: This information is only used for _display_ purposes: it in
    /// no way affects any of the arithmetic of the contract, including
    /// {IERC20-balanceOf} and {IERC20-transfer}.
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /// @dev See {IERC20-totalSupply}.
    function totalSupply() public view virtual override returns (uint256) {
        return mTotalSupply;
    }

    /// @dev See {IERC20-balanceOf}.
    function balanceOf(address _account) public view virtual override returns (uint256) {
        return mBalances.get(_account);
    }

    /// @dev See {IERC20-transfer}.
    /// Requirements:
    /// - `to` cannot be the zero address.
    /// - the caller must have a balance of at least `amount`.
    function transfer(address _to, uint256 _amount) public virtual override returns (bool) {
        address _owner = _msgSender();
        _transfer(_owner, _to, _amount);
        return true;
    }

    /// @dev See {IERC20-allowance}.
    function allowance(address _owner, address _spender) public view virtual override returns (uint256) {
        return mAllowances[_owner][_spender];
    }

    /// @dev See {IERC20-approve}.
    /// NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
    /// `transferFrom`. This is semantically equivalent to an infinite approval.
    /// Requirements:
    /// - `spender` cannot be the zero address.
    function approve(address _spender, uint256 _amount) public virtual override returns (bool) {
        address _owner = _msgSender();
        require(
            (_amount == 0) || (allowance(_owner, _spender) == 0),
            "approve from non-zero to non-zero allowance"
        );
        _approve(_owner, _spender, _amount);
        return true;
    }

    /// @dev See {IERC20-transferFrom}.
    /// Emits an {Approval} event indicating the updated allowance. This is not
    /// required by the EIP. See the note at the beginning of {ERC20}.
    /// NOTE: Does not update the allowance if the current allowance
    /// is the maximum `uint256`.
    /// Requirements:
    /// - `from` and `to` cannot be the zero address.
    /// - `from` must have a balance of at least `amount`.
    /// - the caller must have allowance for ``from``'s tokens of at least
    /// `amount`.
    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) public virtual override returns (bool) {
        address _spender = _msgSender();
        _spendAllowance(_from, _spender, _amount);
        _transfer(_from, _to, _amount);
        return true;
    }

    /// @dev Atomically increases the allowance granted to `spender` by the caller.
    /// This is an alternative to {approve} that can be used as a mitigation for
    /// problems described in {IERC20-approve}.
    /// Emits an {Approval} event indicating the updated allowance.
    /// Requirements:
    /// - `spender` cannot be the zero address.
    function increaseAllowance(address _spender, uint256 _addedValue) public virtual returns (bool) {
        address _owner = _msgSender();
        _approve(_owner, _spender, allowance(_owner, _spender) + _addedValue);
        return true;
    }

    /// @dev Atomically decreases the allowance granted to `spender` by the caller.
    /// This is an alternative to {approve} that can be used as a mitigation for
    /// problems described in {IERC20-approve}.
    /// Emits an {Approval} event indicating the updated allowance.
    /// Requirements:
    /// - `spender` cannot be the zero address.
    /// - `spender` must have allowance for the caller of at least
    /// `subtractedValue`.
    function decreaseAllowance(address _spender, uint256 _subtractedValue) public virtual returns (bool) {
        address _owner = _msgSender();
        uint256 _currentAllowance = allowance(_owner, _spender);
        require(_currentAllowance >= _subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_owner, _spender, _currentAllowance - _subtractedValue);
        }

        return true;
    }

    /// @dev Moves `amount` of tokens from `sender` to `recipient`.
    /// This internal function is equivalent to {transfer}, and can be used to
    /// e.g. implement automatic token fees, slashing mechanisms, etc.
    /// Emits a {Transfer} event.
    /// Requirements:
    /// - `from` cannot be the zero address.
    /// - `to` cannot be the zero address.
    /// - `from` must have a balance of at least `amount`.
    function _transfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual {
        require(_from != address(0), "ERC20: transfer from the zero address");
        require(_to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(_from, _to, _amount);

        uint256 _fromBalance = mBalances.get(_from);
        require(_fromBalance >= _amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            uint256 _newBalance = _fromBalance - _amount;
            if (_newBalance == 0) {
                mBalances.remove(_from);
            } else {
                mBalances.set(_from, _newBalance);
            }
        }
        mBalances.plus(_to, _amount);

        emit Transfer(_from, _to, _amount);

        _afterTokenTransfer(_from, _to, _amount);
    }

    ///  @dev Creates `amount` tokens and assigns them to `account`, increasing
    /// the total supply.
    /// Emits a {Transfer} event with `from` set to the zero address.
    /// Requirements:
    /// - `account` cannot be the zero address.
    function _mint(address _account, uint256 _amount) internal virtual {
        require(_account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), _account, _amount);

        mTotalSupply += _amount;
        mBalances.plus(_account, _amount);
        emit Transfer(address(0), _account, _amount);

        _afterTokenTransfer(address(0), _account, _amount);
    }

    /// @dev Destroys `amount` tokens from `account`, reducing the
    /// total supply.
    /// Emits a {Transfer} event with `to` set to the zero address.
    /// Requirements:
    /// - `account` cannot be the zero address.
    /// - `account` must have at least `amount` tokens.
    function _burn(address _account, uint256 _amount) internal virtual {
        require(_account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(_account, address(0), _amount);

        uint256 accountBalance = mBalances.get(_account);
        require(accountBalance >= _amount, "ERC20: burn amount exceeds balance");
        unchecked {
            uint256 newBalance = accountBalance - _amount;
            if (newBalance == 0) {
                mBalances.remove(_account);
            } else {
                mBalances.set(_account, newBalance);
            }
        }
        mTotalSupply -= _amount;

        emit Transfer(_account, address(0), _amount);

        _afterTokenTransfer(_account, address(0), _amount);
    }

    /// @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
    /// This internal function is equivalent to `approve`, and can be used to
    /// e.g. set automatic allowances for certain subsystems, etc.
    /// Emits an {Approval} event.
    /// Requirements:
    /// - `owner` cannot be the zero address.
    /// - `spender` cannot be the zero address.
    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal virtual {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(_spender != address(0), "ERC20: approve to the zero address");

        mAllowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    /// @dev Updates `owner` s allowance for `spender` based on spent `amount`.
    /// Does not update the allowance amount in case of infinite allowance.
    /// Revert if not enough allowance is available.
    /// Might emit an {Approval} event.
    function _spendAllowance(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal virtual {
        uint256 _currentAllowance = allowance(_owner, _spender);
        if (_currentAllowance != type(uint256).max) {
            require(_currentAllowance >= _amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(_owner, _spender, _currentAllowance - _amount);
            }
        }
    }

    /// @dev Hook that is called before any transfer of tokens. This includes
    /// minting and burning.
    /// Calling conditions:
    /// - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
    /// will be transferred to `to`.
    /// - when `from` is zero, `amount` tokens will be minted for `to`.
    /// - when `to` is zero, `amount` of ``from``'s tokens will be burned.
    /// - `from` and `to` are never both zero.
    /// To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual {}

    /// @dev Hook that is called after any transfer of tokens. This includes
    /// minting and burning.
    /// Calling conditions:
    /// - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
    /// has been transferred to `to`.
    /// - when `from` is zero, `amount` tokens have been minted for `to`.
    /// - when `to` is zero, `amount` of ``from``'s tokens have been burned.
    /// - `from` and `to` are never both zero.
    /// To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
    function _afterTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual {}


}
