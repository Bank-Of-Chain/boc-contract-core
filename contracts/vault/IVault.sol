// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../exchanges/IExchangeAggregator.sol";

interface IVault {

    struct StrategyParams {
        //last report timestamp
        uint256 lastReport;
        //total asset
        uint256 totalDebt;
        uint256 profitLimitRatio;
        uint256 lossLimitRatio;
        bool enforceChangeLimit;
    }

    struct StrategyAdd {
        address strategy;
        uint256 profitLimitRatio;
        uint256 lossLimitRatio;
    }

    event AddAsset(address _asset);
    event RemoveAsset(address _asset);
    event AddStrategies(address[] _strategies);
    event RemoveStrategies(address[] _strategies);
    event Mint(
        address _account,
        address[] _assets,
        uint256[] _amounts,
        uint256 _mintAmount
    );
    event Burn(
        address _account,
        address _asset,
        uint256 _amount,
        uint256 _burnAmount
    );
    event BurnWithoutExchange(
        address _account,
        address[] _assets,
        uint256[] _amounts,
        uint256 _burnAmount
    );
    event Exchange(
        address _srcAsset,
        uint256 _srcAmount,
        address _distAsset,
        uint256 _distAmount
    );
    event Redeem(address _strategy, uint256 _amount);
    event RemoveStrategyFromQueue(address[] _strategies);
    event SetEmergencyShutdown(bool _shutdown);
    event RebasePaused();
    event RebaseUnpaused();
    event RebaseThresholdUpdated(uint256 _threshold);
    event MaxSupplyDiffChanged(uint256 maxSupplyDiff);
    event TrusteeFeeBpsChanged(uint256 _basis);
    event TreasuryAddressChanged(address _address);
    event SetAdjustPositionPeriod(bool _adjustPositionPeriod);
    event RedeemFeeUpdated(uint256 _redeemFeeBps);
    event SetWithdrawalQueue(address[] queues);

    /// @notice Version of vault
    function getVersion() external pure returns (string memory);

    /// @notice Minting USDi supported assets
    function getSupportAssets() external view returns (address[] memory assets);

    /// @notice Assets held by Vault
    function getTrackedAssets() external view returns (address[] memory assets);

    /// @notice Vault holds asset value directly in USD
    function valueOfTrackedTokens() external view returns (uint256 totalValue);

    /// @notice Vault total asset in USD
    function totalAssets() external view returns (uint256);

    /// @notice All strategies
    function getStrategies()
    external
    view
    returns (address[] memory strategies);

    /// @notice estimate Minting USDi with stablecoins
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @dev Support single asset or multi-assets
    /// @return unitAdjustedDeposit  assets amount by Scale up to 18 decimal
    /// @return priceAdjustedDeposit   usdi amount
    function estimateMint(address[] memory _assets, uint256[] memory _amounts) external view returns (uint256 unitAdjustedDeposit, uint256 priceAdjustedDeposit);

    /// @notice Minting USDi with stablecoins
    /// @param _assets Address of the asset being deposited
    /// @param _amounts Amount of the asset being deposited
    /// @dev Support single asset or multi-assets
    function mint(address[] memory _assets, uint256[] memory _amounts, uint256 _minimumUsdiAmount) external returns (uint256 usdiAmount);

    /// @notice burn USDi,return stablecoins
    /// @param _amount Amount of USDi to burn
    /// @param _asset one of StableCoin asset
    /// @param _minimumUnitAmount Minimum stablecoin units to receive in return
    function burn(uint256 _amount,
        address _asset,
        uint256 _minimumUnitAmount,
        bool _needExchange,
        IExchangeAggregator.ExchangeToken[] memory _exchangeTokens
    ) external returns (address[] memory _assets, uint256[] memory _amounts);

    /// @notice Change USDi supply with Vault total assets.
    function rebase() external;

    /// @notice Allocate funds in Vault to strategies.
    function lend(
        address _strategy,
        IExchangeAggregator.ExchangeToken[] calldata _exchangeTokens
    ) external;

    /// @notice Withdraw the funds from specified strategy.
    function redeem(address _strategy, uint256 _amount) external;

    function exchange(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        IExchangeAggregator.ExchangeParam memory exchangeParam
    ) external returns (uint256);

    function report(uint256 _strategyAsset) external;
    /// @notice Shutdown the vault when an emergency occurs, cannot mint/burn.
    function setEmergencyShutdown(bool active) external;

    /// @notice set adjustPositionPeriod true when adjust position occurs, cannot remove add asset/strategy and cannot mint/burn.
    function setAdjustPositionPeriod(bool _adjustPositionPeriod) external;

    /**
     * @dev Set a minimum amount of OUSD in a mint or redeem that triggers a
         * rebase
         * @param _threshold OUSD amount with 18 fixed decimals.
         */
    function setRebaseThreshold(uint256 _threshold) external;

    /**
     * @dev Set a fee in basis points to be charged for a redeem.
         * @param _redeemFeeBps Basis point fee to be charged
         */
    function setRedeemFeeBps(uint256 _redeemFeeBps) external;

    /**
        * @dev Sets the maximum allowable difference between
         * total supply and backing assets' value.
         */
    function setMaxSupplyDiff(uint256 _maxSupplyDiff) external;
    /**
     * @dev Sets the treasuryAddress that can receive a portion of yield.
         *      Setting to the zero address disables this feature.
         */
    function setTreasuryAddress(address _address) external;

    /**
     * @dev Sets the TrusteeFeeBps to the percentage of yield that should be
         *      received in basis points.
         */
    function setTrusteeFeeBps(uint256 _basis) external;

    //advance queue
    function setWithdrawalQueue(address[] memory queues) external;

    function setStrategyEnforceChangeLimit(address _strategy, bool _enabled) external;

    function setStrategySetLimitRatio(
        address _strategy,
        uint256 _lossRatioLimit,
        uint256 _profitLimitRatio
    ) external;

    /***************************************
                       Pause
       ****************************************/

    /**
     * @dev Set the deposit paused flag to true to prevent rebasing.
     */
    function pauseRebase() external;

    /**
     * @dev Set the deposit paused flag to true to allow rebasing.
     */
    function unpauseRebase() external;


    /// @notice Added support for specific asset.
    function addAsset(address _asset) external;

    /// @notice Remove support for specific asset.
    function removeAsset(address _asset) external;

    /// @notice Add strategy to strategy list
    /// @dev The strategy added to the strategy list,
    ///      Vault may invest funds into the strategy,
    ///      and the strategy will invest the funds in the 3rd protocol
    function addStrategy(StrategyAdd[] memory strategyAdds) external;


    /// @notice Remove strategy from strategy list
    /// @dev The removed policy withdraws funds from the 3rd protocol and returns to the Vault
    function removeStrategy(address[] memory _strategies) external;

    function forceRemoveStrategy(address _strategy) external;


    /***************************************
                     WithdrawalQueue
     ****************************************/
    function getWithdrawalQueue() external view returns (address[] memory);

    function removeStrategyFromQueue(address[] memory _strategies) external;

    //adjust Position Period
    function adjustPositionPeriod() external view returns (bool);
    // emergency shutdown
    function emergencyShutdown() external view returns (bool);
    // Pausing bools
    function rebasePaused() external view returns (bool);
    // Mints over this amount automatically rebase. 18 decimals.
    function rebaseThreshold() external view returns (uint256);
    // allow max supply diff
    function maxSupplyDiff() external view returns (uint256);
    // Amount of yield collected in basis points
    function trusteeFeeBps() external view returns (uint256);
    // Redemption fee in basis points
    function redeemFeeBps() external view returns (uint256);
    //all strategy asset
    function totalDebt() external view returns (uint256);

    //exchangeManager
    function exchangeManager() external view returns (address);
    // strategy info
    function strategies(address _strategy) external view returns (StrategyParams memory);

    //withdraw strategy set
    function withdrawQueue() external view returns (address[] memory);

    /// @notice Address of treasury
    function treasury() external view returns (address);

    /// @notice Address of price oracle
    function valueInterpreter() external view returns (address);

    function accessControlProxy() external view returns (address);

}
