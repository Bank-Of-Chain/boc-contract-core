// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import "../exchanges/IExchangeAggregator.sol";

/// @title IVault interface
interface IVault {
    /// @param lastReport The last report timestamp
    /// @param totalDebt The total asset of this strategy
    /// @param profitLimitRatio The limited ratio of profit
    /// @param lossLimitRatio The limited ratio for loss
    /// @param enforceChangeLimit The switch of enforce change Limit
    /// @param lastClaim The last claim timestamp
    /// @param targetDebt The max target debt
    struct StrategyParams {
        uint256 lastReport;
        uint256 totalDebt;
        uint256 profitLimitRatio;
        uint256 lossLimitRatio;
        bool enforceChangeLimit;
        uint256 lastClaim;
        uint256 targetDebt;
    }

    /// @param strategy The new strategy to add
    /// @param profitLimitRatio The limited ratio of profit
    /// @param lossLimitRatio The limited ratio for loss
    /// @param targetDebt The max target debt
    struct StrategyAdd {
        address strategy;
        uint256 profitLimitRatio;
        uint256 lossLimitRatio;
        uint256 targetDebt;
    }

    /// @param _asset The new asset to add
    event AddAsset(address _asset);

    /// @param _asset The new asset to remove
    event RemoveAsset(address _asset);

    /// @param _strategies The new strategy list to add
    event AddStrategies(address[] _strategies);

    /// @param _strategies The multi strategies to remove
    event RemoveStrategies(address[] _strategies);

    /// @param _strategy One strategy to remove
    event RemoveStrategyByForce(address _strategy);

    /// @param _account The minter
    /// @param _assets The address list of the assets depositing
    /// @param _amounts The amount of the asset depositing
    /// @param _mintAmount The amount of the asset minting
    event Mint(address _account, address[] _assets, uint256[] _amounts, uint256 _mintAmount);

    /// @param _account The owner of token burning
    /// @param _amounts The amount of the USDi/ETHi token burning
    /// @param _actualAmount The received amount actually
    /// @param _shareAmount The amount of the shares burning
    /// @param _assets The address list of assets to receive
    /// @param _amounts The amount list of assets to receive
    event Burn(
        address _account,
        uint256 _amount,
        uint256 _actualAmount,
        uint256 _shareAmount,
        address[] _assets,
        uint256[] _amounts
    );

    /// @param  _platform The platform used for the exchange
    /// @param _srcAsset The address of asset exchange from
    /// @param _srcAmount The amount of asset exchange from
    /// @param _distAsset The address of asset exchange to
    /// @param _distAmount The amount of asset exchange to
    event Exchange(
        address _platform,
        address _srcAsset,
        uint256 _srcAmount,
        address _distAsset,
        uint256 _distAmount
    );

    /// @param  _strategy The specified strategy to redeem
    /// @param _debtChangeAmount The amount to redeem in USD(USDi)/ETH(ETHi)
    /// @param _assets The address list of asset redeeming
    /// @param _amounts The amount list of asset redeeming
    event Redeem(address _strategy, uint256 _debtChangeAmount, address[] _assets, uint256[] _amounts);

    /// @param  _strategy The specified strategy to lend
    /// @param _wants The address list of token wanted
    /// @param _amounts The amount list of token wanted
    /// @param _lendValue The value to lend in USD(USDi)/ETH(ETHi)
    event LendToStrategy(
        address indexed _strategy,
        address[] _wants,
        uint256[] _amounts,
        uint256 _lendValue
    );

    /// @param  _strategy The specified strategy repaying from
    /// @param _strategyWithdrawValue The value of `_strategy` to withdraw
    /// @param _strategyTotalValue The total value of `_strategy` in USD(USDi)/ETH(ETHi)
    /// @param _assets The address list of asset repaying from `_strategy`
    /// @param _amounts The amount list of asset repaying from `_strategy`
    event RepayFromStrategy(
        address indexed _strategy,
        uint256 _strategyWithdrawValue,
        uint256 _strategyTotalValue,
        address[] _assets,
        uint256[] _amounts
    );

    /// @param _strategies The strategy list to remove
    event RemoveStrategyFromQueue(address[] _strategies);

    /// @param _shutdown The new boolean value of the emergency shutdown switch
    event SetEmergencyShutdown(bool _shutdown);

    event RebasePaused();
    event RebaseUnpaused();

    /// @param _threshold is the numerator and the denominator is 1e7. x/1e7
    event RebaseThresholdUpdated(uint256 _threshold);

    /// @param _basis the new value of `trusteeFeeBps`
    event TrusteeFeeBpsChanged(uint256 _basis);

    /// @param _maxTimestampBetweenTwoReported the new value of `maxTimestampBetweenTwoReported`
    event MaxTimestampBetweenTwoReportedChanged(uint256 _maxTimestampBetweenTwoReported);

    /// @param _minCheckedStrategyTotalDebt the new value of `minCheckedStrategyTotalDebt`
    event MinCheckedStrategyTotalDebtChanged(uint256 _minCheckedStrategyTotalDebt);

    /// @param _minimumInvestmentAmount the new value of `minimumInvestmentAmount`
    event MinimumInvestmentAmountChanged(uint256 _minimumInvestmentAmount);

    /// @param _address the new treasury address
    event TreasuryAddressChanged(address _address);

    /// @param _address the new exchange manager address
    event ExchangeManagerAddressChanged(address _address);

    /// @param _adjustPositionPeriod the new boolean value of `adjustPositionPeriod`
    event SetAdjustPositionPeriod(bool _adjustPositionPeriod);

    /// @param _redeemFeeBps the new value of `_redeemFeeBps`
    event RedeemFeeUpdated(uint256 _redeemFeeBps);

    /// @param _queues the new queue to withdraw
    event SetWithdrawalQueue(address[] _queues);

    /// @param _totalShares The total shares when rebasing
    /// @param _totalValue The total value when rebasing
    /// @param _newUnderlyingUnitsPerShare The new value of `underlyingUnitsPerShare` when rebasing
    event Rebase(uint256 _totalShares, uint256 _totalValue, uint256 _newUnderlyingUnitsPerShare);

    /// @param  _strategy The strategy for reporting
    /// @param _gain The gain in USD(USDi)/ETH(ETHi) units for this report
    /// @param _loss The loss in USD(USDi)/ETH(ETHi) units for this report
    /// @param _lastStrategyTotalDebt The total debt of `_strategy` for last report
    /// @param _nowStrategyTotalDebt The total debt of `_strategy` for this report
    /// @param _type The type of lend operations
    event StrategyReported(
        address indexed _strategy,
        uint256 _gain,
        uint256 _loss,
        uint256 _lastStrategyTotalDebt,
        uint256 _nowStrategyTotalDebt,
        uint256 _type
    );

    /// @param _totalDebtOfBeforeAdjustPosition The total debt Of before adjust position
    /// @param _trackedAssets The address list of assets tracked
    /// @param _vaultCashDetatil The assets's balance list of vault
    /// @param _vaultBufferCashDetail The amount list of assets transfer from vault buffer to vault
    event StartAdjustPosition(
        uint256 _totalDebtOfBeforeAdjustPosition,
        address[] _trackedAssets,
        uint256[] _vaultCashDetatil,
        uint256[] _vaultBufferCashDetail
    );

    /// @param _transferValue The total value to transfer on this adjust position
    /// @param _redeemValue The total value to redeem on this adjust position
    /// @param _totalDebt The all strategy asset value
    /// @param _totalValueOfAfterAdjustPosition The total asset value Of vault after adjust position
    /// @param _totalValueOfBeforeAdjustPosition The total asset value Of vault before adjust position
    event EndAdjustPosition(
        uint256 _transferValue,
        uint256 _redeemValue,
        uint256 _totalDebt,
        uint256 _totalValueOfAfterAdjustPosition,
        uint256 _totalValueOfBeforeAdjustPosition
    );

    /// @param _pegTokenAmount The amount of the pegged token
    /// @param _assets The address list of asset transfer from vault buffer to vault
    /// @param _amounts The amount list of asset transfer from vault buffer to vault
    event PegTokenSwapCash(uint256 _pegTokenAmount, address[] _assets, uint256[] _amounts);

    /// @notice Return the version of vault
    function getVersion() external pure returns (string memory);

    /// @notice Return the supported assets to mint USDi/ETHi
    function getSupportAssets() external view returns (address[] memory _assets);

    /// @notice Check '_asset' is supported or not
    function checkIsSupportAsset(address _asset) external view;

    /// @notice Return the assets held by vault
    function getTrackedAssets() external view returns (address[] memory _assets);

    /// @notice Vault holds asset value directly in USD(USDi)/ETH(ETHi)(1e18)
    function valueOfTrackedTokens() external view returns (uint256 _totalValue);

    /// @notice Return the asset value in USD(USDi)/ETH(ETHi) held by vault and vault buffer
    function valueOfTrackedTokensIncludeVaultBuffer() external view returns (uint256 _totalValue);

    /// @notice Return the total asset value in USD(USDi)/ETH(ETHi) (1e18) held by vault;
    function totalAssets() external view returns (uint256);

    /// @notice Return the total asset in USD(USDi)/ETH(ETHi)(1e18) held by vault and vault buffer;
    function totalAssetsIncludeVaultBuffer() external view returns (uint256);

    /// @notice Return the total value(by chainlink price) in USD(1e18) held by vault
    function totalValue() external view returns (uint256);

    /// @notice Start adjust position
    function startAdjustPosition() external;

    /// @notice End adjust position
    function endAdjustPosition() external;

    /// @notice Return underlying token per share token
    function underlyingUnitsPerShare() external view returns (uint256);

    /// @notice Get pegToken price in USD(USDi)/ETH(ETHi)(1e18)
    function getPegTokenPrice() external view returns (uint256);

    /// @dev Calculate total value of all assets held in Vault.
    /// @return _value Total value(by oracle price) in USD (1e18)
    function totalValueInVault() external view returns (uint256 _value);

    /// @dev Calculate total value of all assets held in Strategies.
    /// @return _value Total value(by oracle price) in USD (1e18)
    function totalValueInStrategies() external view returns (uint256 _value);

    /// @notice Return all strategy addresses
    function getStrategies() external view returns (address[] memory _strategies);

    /// @notice Check '_strategy' is active or not
    function checkActiveStrategy(address _strategy) external view;

    /// @notice Estimate the amount of shares to mint with imput stablecoins
    /// @dev Support single asset or multi-assets
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @return _shareAmount The amount of shares estimated to mint
    function estimateMint(
        address[] memory _assets,
        uint256[] memory _amounts
    ) external view returns (uint256 _shareAmount);

    /// @notice Minting the USDi/ETHi ticket with stablecoins(USDi)/ETH(ETHi)
    /// @dev Support single asset or multi-assets
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @return _shareAmount The amount shares minted
    function mint(
        address[] memory _assets,
        uint256[] memory _amounts,
        uint256 _minimumAmount
    ) external payable returns (uint256 _shareAmount);

    /// @notice Burn USDi/ETHi,return stablecoins(USDi)/xETH(ETHi);xETH is like wETH,sETH,stETH,rETH etc.
    /// @param _amount Amount of USDi/ETHi to burn
    /// @param _minimumAmount Minimum USD(USDi)/ETH(ETHi) to receive in return
    /// @param _redeemFeeBps Redemption fee in basis points
    /// @param _trusteeFeeBps Amount of yield collected in basis points
    /// @return _assets The address list of assets to receive
    /// @return _amounts The amount list of assets to receive
    /// @return _actuallyReceivedAmount The value of the assets in USD(USDi)/ETH(ETHi)
    function burn(
        uint256 _amount,
        uint256 _minimumAmount,
        uint256 _redeemFeeBps,
        uint256 _trusteeFeeBps
    )
        external
        returns (address[] memory _assets, uint256[] memory _amounts, uint256 _actuallyReceivedAmount);

    /// @notice Change USDi/ETHi supply with Vault total assets.
    /// @param _trusteeFeeBps Amount of yield collected in basis points
    function rebase(uint256 _trusteeFeeBps) external;

    /// @notice Allocate funds in Vault to strategies.
    /// @param _strategy The specified strategy to lend
    /// @param _tokens want tokens
    /// @param _amounts the amount of each tokens
    /// @param _minDeltaAssets the minimum allowable asset increment
    /// @return _deltaAssets The amount of newly added assets
    function lend(
        address _strategy,
        address[] memory _tokens,
        uint256[] memory _amounts,
        uint256 _minDeltaAssets
    ) external returns (uint256 _deltaAssets);

    /// @notice Withdraw the funds from specified strategy.
    /// @param _strategy The specified strategy to redeem
    /// @param _amount The amount to redeem in USD(USDi)/ETH(ETHi)
    /// @param _outputCode The code of output
    function redeem(
        address _strategy,
        uint256 _amount,
        uint256 _outputCode
    ) external returns (address[] memory _assets, uint256[] memory _amounts);

    /// @dev Exchange from '_fromToken' to '_toToken'
    /// @param _fromToken The token swap from
    /// @param _toToken The token swap to
    /// @param _amount The amount to swap
    /// @param _exchangeParam The struct of ExchangeParam, see {ExchangeParam} struct
    /// @return _exchangeAmount The real amount to exchange
    /// Emits a {Exchange} event.
    function exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory _exchangeParam
    ) external returns (uint256);

    /// @dev Report the current asset of strategy caller
    /// @param _strategies The address list of strategies to report
    /// Requirement: only keeper call
    /// Emits a {StrategyReported} event.
    function reportByKeeper(address[] memory _strategies) external;

    /// @dev Report the current asset of strategy caller
    /// Requirement: only the strategy caller is active
    /// Emits a {StrategyReported} event.
    function reportWithoutClaim() external;

    /// @dev Report the current asset of strategy caller
    /// Emits a {StrategyReported} event.
    function report() external;

    /// @notice Shutdown the vault when an emergency occurs, cannot mint/burn.
    function setEmergencyShutdown(bool _active) external;

    /// @notice Sets adjustPositionPeriod true when adjust position occurs, cannot remove add asset/strategy and cannot mint/burn.
    function setAdjustPositionPeriod(bool _adjustPositionPeriod) external;

    /// @dev Sets a minimum difference ratio automatically rebase.
    /// @param _threshold _threshold is the numerator and the denominator is 1e7 (x/1e7).
    function setRebaseThreshold(uint256 _threshold) external;

    /// @dev Sets a fee in basis points to be charged for a redeem.
    /// @param _redeemFeeBps Basis point fee to be charged
    function setRedeemFeeBps(uint256 _redeemFeeBps) external;

    /// @dev Sets the treasuryAddress that can receive a portion of yield.
    ///      Setting to the zero address disables this feature.
    function setTreasuryAddress(address _address) external;

    /// @dev Sets the exchangeManagerAddress that can receive a portion of yield.
    function setExchangeManagerAddress(address _exchangeManagerAddress) external;

    /// @dev Sets the TrusteeFeeBps to the percentage of yield that should be
    ///      received in basis points.
    function setTrusteeFeeBps(uint256 _basis) external;

    /// @notice Sets '_queues' as advance withdrawal queue
    function setWithdrawalQueue(address[] memory _queues) external;

    /// @notice Sets '_enabled' to the 'enforceChangeLimit' field of '_strategy'
    function setStrategyEnforceChangeLimit(address _strategy, bool _enabled) external;

    /// @notice Sets '_lossRatioLimit' to the 'lossRatioLimit' field of '_strategy'
    ///         Sets '_profitLimitRatio' to the 'profitLimitRatio' field of '_strategy'
    function setStrategySetLimitRatio(
        address _strategy,
        uint256 _lossRatioLimit,
        uint256 _profitLimitRatio
    ) external;

    /// @dev Sets the deposit paused flag to true to prevent rebasing.
    function pauseRebase() external;

    /// @dev Sets the deposit paused flag to true to allow rebasing.
    function unpauseRebase() external;

    /// @notice Added support for specific asset.
    function addAsset(address _asset) external;

    /// @notice Remove support for specific asset.
    function removeAsset(address _asset) external;

    /// @notice Add strategy to strategy list
    /// @dev The strategy added to the strategy list,
    ///      Vault may invest funds into the strategy,
    ///      and the strategy will invest the funds in the 3rd protocol
    function addStrategies(StrategyAdd[] memory _strategyAdds) external;

    /// @notice Remove multi strategies from strategy list
    /// @dev The removed policy withdraws funds from the 3rd protocol and returns to the Vault
    function removeStrategies(address[] memory _strategies) external;

    /// @notice Forced to remove the '_strategy'
    function forceRemoveStrategy(address _strategy) external;

    /////////////////////////////////////////
    //           WithdrawalQueue           //
    /////////////////////////////////////////

    /// @notice Return the withdrawal queue
    function getWithdrawalQueue() external view returns (address[] memory);

    /// @notice Remove multi strategies from the withdrawal queue
    /// @param _strategies multi strategies to remove
    function removeStrategyFromQueue(address[] memory _strategies) external;

    /// @notice Return the boolean value of `adjustPositionPeriod`
    function adjustPositionPeriod() external view returns (bool);

    /// @notice Return the status of emergency shutdown switch
    function emergencyShutdown() external view returns (bool);

    /// @notice Return the status of rebase paused switch
    function rebasePaused() external view returns (bool);

    /// @notice Return the rebaseThreshold value,
    /// over this difference ratio automatically rebase.
    /// rebaseThreshold is the numerator and the denominator is 1e7,
    /// the real ratio is `rebaseThreshold`/1e7.
    function rebaseThreshold() external view returns (uint256);

    /// @notice Return the Amount of yield collected in basis points
    function trusteeFeeBps() external view returns (uint256);

    /// @notice Return the redemption fee in basis points
    function redeemFeeBps() external view returns (uint256);

    /// @notice Return the total asset of all strategy
    function totalDebt() external view returns (uint256);

    /// @notice Return the exchange manager address
    function exchangeManager() external view returns (address);

    /// @notice Return all info of '_strategy'
    function strategies(address _strategy) external view returns (StrategyParams memory);

    /// @notice Return withdraw strategy address list
    function withdrawQueue() external view returns (address[] memory);

    /// @notice Return the address of treasury
    function treasury() external view returns (address);

    /// @notice Return the address of price oracle
    function valueInterpreter() external view returns (address);

    /// @notice Return the address of access control proxy contract
    function accessControlProxy() external view returns (address);

    /// @notice Sets the minimum strategy total debt
    ///     that will be checked for the strategy reporting
    function setMinCheckedStrategyTotalDebt(uint256 _minCheckedStrategyTotalDebt) external;

    /// @notice Return the minimum strategy total debt
    ///     that will be checked for the strategy reporting
    function minCheckedStrategyTotalDebt() external view returns (uint256);

    /// @notice Sets the maximum timestamp between two reported
    function setMaxTimestampBetweenTwoReported(uint256 _maxTimestampBetweenTwoReported) external;

    /// @notice The maximum timestamp between two reported
    function maxTimestampBetweenTwoReported() external view returns (uint256);

    /// @notice Sets the minimum investment amount
    function setMinimumInvestmentAmount(uint256 _minimumInvestmentAmount) external;

    /// @notice Return the minimum investment amount
    function minimumInvestmentAmount() external view returns (uint256);

    /// @notice Sets the address of vault buffer contract
    function setVaultBufferAddress(address _address) external;

    /// @notice Return the address of vault buffer contract
    function vaultBufferAddress() external view returns (address);

    /// @notice Sets the address of PegToken contract
    function setPegTokenAddress(address _address) external;

    /// @notice Return the address of PegToken contract
    function pegTokenAddress() external view returns (address);

    /// @notice Return the vault type  0-USDi,1-ETHi
    function vaultType() external view returns (uint256);

    /// @notice Sets the new implement contract address
    function setAdminImpl(address _newImpl) external;

    /// @notice check one asset is tracked or not
    function isTrackedAssets(address _token) external returns(bool);

    /// @notice Sets the new target debts for multi strategies
    function setStrategyTargetDebts(address[] memory _strategies, uint256[] memory _newTargetDebts) external;
    
    /// @notice Increases the target debts for multi strategies
    function increaseStrategyTargetDebts(address[] memory _strategies, uint256[] memory _addAmounts) external;

    /// @dev Exchange from '_fromToken' to '_toToken'
    /// @param _fromToken The token swap from
    /// @param _toToken The token swap to
    /// @param _fromAmount The amount of `_fromToken` to swap
    /// @param _platformType The different platform, 0 =>1Inch,1 =>paraswap
    /// @return _success The exchange is success or fail
    /// @return _returnAmount The return amount of `_toToken`
    /// Emits a {Exchange} event.
    function exchange(
        address _fromToken,
        address _toToken,
        uint256 _fromAmount,
        bytes calldata _calldata,
        uint16 _platformType
    ) external payable returns (bool _success, uint256 _returnAmount);

    /// @notice Vault holds asset value directly in USD(USDi)/ETH(ETHi)(1e18)
    function valueOfTrackedTokensInVaultBuffer() external view returns (uint256);

    /// @notice Return 1inch router address
    function oneInchRouter() external view returns(address);
    /// @notice Return paraswap router address
    function paraRouter() external view returns(address);
    /// @notice Return paraswap transfer proxy address
    function paraTransferProxy() external view returns(address);

    /// @notice Sets new 1inch router address
    function set1inchRouter(address _newRouter) external;
    /// @notice Sets new paraswap router address
    function setParaRouter(address _newRouter) external;
    /// @notice Sets new paraswap transfer proxy address
    function setParaTransferProxy(address _newRouter) external;
}
