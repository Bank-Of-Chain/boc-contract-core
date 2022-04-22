// SPDX-License-Identifier: AGPL-3.0-or-later



pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../access-control/AccessControlMixin.sol";
import "../library/StableMath.sol";

import "hardhat/console.sol";
import "../library/BocRoles.sol";

contract USDi is Initializable, IERC20Upgradeable, ReentrancyGuardUpgradeable, AccessControlMixin
{
    using StableMath for uint256;

    event TotalSupplyChanged(
        uint256 _newSupply,
        uint256 _rebasingCredits,
        uint256 _rebasingCreditsPerToken
    );
    event RebaseLocked(address _account);
    event RebaseUnlocked(address _account);

    enum RebaseOptions {
        NotSet,
        OptOut,
        OptIn
    }

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 private constant MAX_SUPPLY = type(uint256).max;
    uint256 public _totalSupply;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _creditBalances;
    uint256 private _rebasingCredits;
    uint256 private _rebasingCreditsPerToken;
    // Frozen address/credits are non rebasing (value is held in contracts which
    // do not receive yield unless they explicitly opt in)
    uint256 public nonRebasingSupply;
    mapping(address => uint256) public nonRebasingCreditsPerToken;
    mapping(address => RebaseOptions) public rebaseState;
    address public vault;

    modifier onlyVault {
        console.log('vault: %s', vault);
        console.log('msg.sender: %s', msg.sender);
        require(msg.sender == vault);
        _;
    }

    /**
     * @dev Sets the values for `name`, `symbol`, and `decimals`. All three of
     * these values are immutable: they can only be set once during
     * construction.
     * @notice To avoid variable shadowing appended `Arg` after arguments name.
     */
    function initialize(
        string calldata nameArg,
        string calldata symbolArg,
        uint8 decimalsArg,
        address _vault,
        address _accessControlProxy
    ) external initializer {
        _name = nameArg;
        _symbol = symbolArg;
        _decimals = decimalsArg;
        vault = _vault;
        _initAccessControl(_accessControlProxy);
        _rebasingCreditsPerToken = 1e27;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    /**
     * @return The total supply of USDi.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @return High resolution rebasingCreditsPerToken
     */
    function rebasingCreditsPerToken() public view returns (uint256) {
        return _rebasingCreditsPerToken;
    }

    /**
     * @return High resolution total number of rebasing credits
     */
    function rebasingCredits() public view returns (uint256) {
        return _rebasingCredits;
    }

    /**
     * @dev Gets the balance of the specified address.
     * @param _account Address to query the balance of.
     * @return A uint256 representing the amount of base units owned by the
     *         specified address.
     */
    function balanceOf(address _account)
    public
    view
    override
    returns (uint256)
    {
        if (_creditBalances[_account] == 0) return 0;
        return
        _creditBalances[_account].divPrecisely(_creditsPerToken(_account));
    }

    /**
     * @dev Gets the credits balance of the specified address.
     * @dev Backwards compatible with old low res credits per token.
     * @param _account The address to query the balance of.
     * @return (uint256) Credit balance and credits per token of the
     *         address
     */
    function creditsBalanceOf(address _account) public view returns (uint256) {
        return _creditBalances[_account];
    }

    /**
     * @dev Transfer tokens to a specified address.
     * @param _to the address to transfer to.
     * @param _value the amount to be transferred.
     * @return true on success.
     */
    function transfer(address _to, uint256 _value)
    public
    override
    returns (bool)
    {
        require(_to != address(0), "Transfer to zero address");
        require(
            _value <= balanceOf(msg.sender),
            "Transfer greater than balance"
        );

        _executeTransfer(msg.sender, _to, _value);

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    /**
     * @dev Transfer tokens from one address to another.
     * @param _from The address you want to send tokens from.
     * @param _to The address you want to transfer to.
     * @param _value The amount of tokens to be transferred.
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public override returns (bool) {
        require(_to != address(0), "Transfer to zero address");
        require(_value <= balanceOf(_from), "Transfer greater than balance");

        _allowances[_from][msg.sender] -= _value;

        _executeTransfer(_from, _to, _value);

        emit Transfer(_from, _to, _value);

        return true;
    }

    /**
     * @dev Update the count of non rebasing credits in response to a transfer
     * @param _from The address you want to send tokens from.
     * @param _to The address you want to transfer to.
     * @param _value Amount of USDi to transfer
     */
    function _executeTransfer(
        address _from,
        address _to,
        uint256 _value
    ) internal {
        bool isNonRebasingTo = _isNonRebasingAccount(_to);
        bool isNonRebasingFrom = _isNonRebasingAccount(_from);

        // Credits deducted and credited might be different due to the
        // differing creditsPerToken used by each account
//        uint256 creditsCredited = _value.mulTruncate(_creditsPerToken(_to));
        uint256 creditsCredited = _calCreditsIncreased(_to, _value);
//        uint256 creditsDeducted = _value.mulTruncate(_creditsPerToken(_from));
        uint256 creditsDeducted = _calCreditsDeducted(_from, _value);

        _creditBalances[_from] = _creditBalances[_from] - creditsDeducted;
        _creditBalances[_to] = _creditBalances[_to] + creditsCredited;

        if (isNonRebasingTo && !isNonRebasingFrom) {
            // Transfer to non-rebasing account from rebasing account, credits
            // are removed from the non rebasing tally
            nonRebasingSupply = nonRebasingSupply + _value;
            // Update rebasingCredits by subtracting the deducted amount
            _rebasingCredits = _rebasingCredits - creditsDeducted;
        } else if (!isNonRebasingTo && isNonRebasingFrom) {
            // Transfer to rebasing account from non-rebasing account
            // Decreasing non-rebasing credits by the amount that was sent
            nonRebasingSupply = nonRebasingSupply - _value;
            // Update rebasingCredits by adding the credited amount
            _rebasingCredits = _rebasingCredits + creditsCredited;
        }else if(!isNonRebasingTo && !isNonRebasingFrom){
            if(creditsCredited - creditsDeducted != 0){
                _rebasingCredits = _rebasingCredits  + creditsCredited - creditsDeducted;
            }
        }
    }

    function _calCreditsIncreased(address _account, uint256 _amount) internal view returns (uint256 _creditsIncreased){
        uint256 _creditBalances = _creditBalances[_account];
        uint256 _creditsPerToken = _creditsPerToken(_account);
        _creditsIncreased = (_creditBalances.divPrecisely(_creditsPerToken) + _amount).mulTruncateCeil(_creditsPerToken) - _creditBalances;
    }

    function _calCreditsDeducted(address _account, uint256 _amount) internal view returns (uint256 _creditsDeducted){
        uint256 _creditBalances = _creditBalances[_account];
        uint256 _creditsPerToken = _creditsPerToken(_account);
        _creditsDeducted =_creditBalances - (_creditBalances.divPrecisely(_creditsPerToken) - _amount).mulTruncateCeil(_creditsPerToken) ;
    }

    /**
     * @dev Function to check the amount of tokens that _owner has allowed to
     *      `_spender`.
     * @param _owner The address which owns the funds.
     * @param _spender The address which will spend the funds.
     * @return The number of tokens still available for the _spender.
     */
    function allowance(address _owner, address _spender)
    public
    view
    override
    returns (uint256)
    {
        return _allowances[_owner][_spender];
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens
     *      on behalf of msg.sender. This method is included for ERC20
     *      compatibility. `increaseAllowance` and `decreaseAllowance` should be
     *      used instead.
     *
     *      Changing an allowance with this method brings the risk that someone
     *      may transfer both the old and the new allowance - if they are both
     *      greater than zero - if a transfer transaction is mined before the
     *      later approve() call is mined.
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(address _spender, uint256 _value)
    public
    override
    returns (bool)
    {
        _allowances[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
     * @dev Increase the amount of tokens that an owner has allowed to
     *      `_spender`.
     *      This method should be used instead of approve() to avoid the double
     *      approval vulnerability described above.
     * @param _spender The address which will spend the funds.
     * @param _addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address _spender, uint256 _addedValue)
    public
    returns (bool)
    {
        _allowances[msg.sender][_spender] += _addedValue;
        emit Approval(msg.sender, _spender, _allowances[msg.sender][_spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner has allowed to
            `_spender`.
     * @param _spender The address which will spend the funds.
     * @param _subtractedValue The amount of tokens to decrease the allowance
     *        by.
     */
    function decreaseAllowance(address _spender, uint256 _subtractedValue)
    public
    returns (bool)
    {
        uint256 oldValue = _allowances[msg.sender][_spender];
        if (_subtractedValue >= oldValue) {
            _allowances[msg.sender][_spender] = 0;
        } else {
            _allowances[msg.sender][_spender] = oldValue - _subtractedValue;
        }
        emit Approval(msg.sender, _spender, _allowances[msg.sender][_spender]);
        return true;
    }

    /**
     * @dev Mints new tokens, increasing totalSupply.
     */
    function mint(address _account, uint256 _amount)
    external
    onlyVault
    {
        _mint(_account, _amount);
    }

    /**
     * @dev Creates `_amount` tokens and assigns them to `_account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address _account, uint256 _amount) internal nonReentrant {
        require(_account != address(0), "Mint to the zero address");

        bool isNonRebasingAccount = _isNonRebasingAccount(_account);
//        uint256 creditAmount = _amount.mulTruncate(_creditsPerToken(_account));
        uint256 creditAmount = _calCreditsIncreased(_account, _amount);
        _creditBalances[_account] += creditAmount;
        // console.log(
        //     "mint %s,amount:%d,creditBalances:%d",
        //     _account,
        //     _amount,
        //     _creditBalances[_account]
        // );
        // If the account is non rebasing and doesn't have a set creditsPerToken
        // then set it i.e. this is a mint from a fresh contract
        if (isNonRebasingAccount) {
            nonRebasingSupply += _amount;
        } else {
            _rebasingCredits += creditAmount;
        }

        _totalSupply += _amount;

        require(_totalSupply < MAX_SUPPLY, "Max supply");

        emit Transfer(address(0), _account, _amount);
    }

    /**
     * @dev Burns tokens, decreasing totalSupply.
     */
    function burn(address account, uint256 amount)
    external
    onlyVault
    {
        _burn(account, amount);
    }

    /**
     * @dev Destroys `_amount` tokens from `_account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `_account` cannot be the zero address.
     * - `_account` must have at least `_amount` tokens.
     */
    function _burn(address _account, uint256 _amount) internal nonReentrant {
        require(_account != address(0), "Burn from the zero address");
        if (_amount == 0) {
            return;
        }

        bool isNonRebasingAccount = _isNonRebasingAccount(_account);
//        uint256 creditAmount = _amount.mulTruncate(_creditsPerToken(_account));
        uint256 creditAmount = _calCreditsDeducted(_account, _amount);
        uint256 currentCredits = _creditBalances[_account];

        // Remove the credits, burning rounding errors
        if (
            currentCredits == creditAmount || currentCredits - 1 == creditAmount
        ) {
            // Handle dust from rounding
            _creditBalances[_account] = 0;
        } else if (currentCredits > creditAmount) {
            _creditBalances[_account] -= creditAmount;
        } else {
            revert("Remove exceeds balance");
        }

        // Remove from the credit tallies and non-rebasing supply
        if (isNonRebasingAccount) {
            nonRebasingSupply -= _amount;
        } else {
            _rebasingCredits -= creditAmount;
        }

        _totalSupply -= _amount;

        emit Transfer(_account, address(0), _amount);
    }

    /**
     * @dev Get the credits per token for an account. Returns a fixed amount
     *      if the account is non-rebasing.
     * @param _account Address of the account.
     */
    function _creditsPerToken(address _account)
    internal
    view
    returns (uint256)
    {
        if (nonRebasingCreditsPerToken[_account] != 0) {
            return nonRebasingCreditsPerToken[_account];
        } else {
            return _rebasingCreditsPerToken;
        }
    }

    /**
     * @dev Is an account using rebasing accounting or non-rebasing accounting?
     *      Also, ensure contracts are non-rebasing if they have not opted in.
     * @param _account Address of the account.
     */
    function _isNonRebasingAccount(address _account) internal returns (bool) {
        bool isContract = AddressUpgradeable.isContract(_account);
        if (isContract && rebaseState[_account] == RebaseOptions.NotSet) {
            _ensureRebasingMigration(_account);
        }
        return nonRebasingCreditsPerToken[_account] > 0;
    }

    /**
     * @dev Ensures internal account for rebasing and non-rebasing credits and
     *      supply is updated following deployment of frozen yield change.
     */
    function _ensureRebasingMigration(address _account) internal {
        if (nonRebasingCreditsPerToken[_account] == 0) {
            if (_creditBalances[_account] == 0) {
                // Since there is no existing balance, we can directly set to
                // high resolution, and do not have to do any other bookkeeping
                nonRebasingCreditsPerToken[_account] = 1e27;
            } else {
                // Migrate an existing account:

                // Set fixed credits per token for this account
                nonRebasingCreditsPerToken[_account] = _rebasingCreditsPerToken;
                // Update non rebasing supply
                nonRebasingSupply += balanceOf(_account);
                // Update credit tallies
                _rebasingCredits -= _creditBalances[_account];
            }
        }
    }

    /**
     * @dev Add a contract address to the non-rebasing exception list. The
     * address's balance will be part of rebases and the account will be exposed
     * to upside and downside.
     */
    function rebaseOptIn() public nonReentrant {
        require(_isNonRebasingAccount(msg.sender), "Account has not opted out");

        // Convert balance into the same amount at the current exchange rate
        uint256 newCreditBalance = (_creditBalances[msg.sender] *
        _rebasingCreditsPerToken) / _creditsPerToken(msg.sender);

        // Decreasing non rebasing supply
        nonRebasingSupply -= balanceOf(msg.sender);

        _creditBalances[msg.sender] = newCreditBalance;

        // Increase rebasing credits, totalSupply remains unchanged so no
        // adjustment necessary
        _rebasingCredits += _creditBalances[msg.sender];

        rebaseState[msg.sender] = RebaseOptions.OptIn;

        // Delete any fixed credits per token
        delete nonRebasingCreditsPerToken[msg.sender];

        emit RebaseUnlocked(msg.sender);
    }

    /**
     * @dev Explicitly mark that an address is non-rebasing.
     */
    function rebaseOptOut() public nonReentrant {
        require(!_isNonRebasingAccount(msg.sender), "Account has not opted in");

        // Increase non rebasing supply
        nonRebasingSupply += balanceOf(msg.sender);
        // Set fixed credits per token
        nonRebasingCreditsPerToken[msg.sender] = _rebasingCreditsPerToken;

        // Decrease rebasing credits, total supply remains unchanged so no
        // adjustment necessary
        _rebasingCredits -= _creditBalances[msg.sender];

        // Mark explicitly opted out of rebasing
        rebaseState[msg.sender] = RebaseOptions.OptOut;

        emit RebaseLocked(msg.sender);
    }

    /**
     * @dev Modify the supply without minting new tokens. This uses a change in
     *      the exchange rate between "credits" and USDi tokens to change balances.
     * @param _newTotalSupply New total supply of USDi.
     */
    function changeSupply(uint256 _newTotalSupply)
    external
    onlyVault
    nonReentrant
    {
        require(_totalSupply > 0, "Cannot increase 0 supply");

        if (_totalSupply == _newTotalSupply) {
            return;
        }

        _totalSupply = _newTotalSupply > MAX_SUPPLY
        ? MAX_SUPPLY
        : _newTotalSupply;

        _rebasingCreditsPerToken = _rebasingCredits.divPrecisely(
            _totalSupply - nonRebasingSupply
        );

        require(_rebasingCreditsPerToken > 0, "Invalid change in supply");

        _totalSupply =
        _rebasingCredits.divPrecisely(_rebasingCreditsPerToken) +
        nonRebasingSupply;

        emit TotalSupplyChanged(
            _totalSupply,
            _rebasingCredits,
            _rebasingCreditsPerToken
        );
    }
}
