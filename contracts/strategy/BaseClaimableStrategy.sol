// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "./BaseStrategy.sol";
import "./IClaimableStrategy.sol";
import "../harvester/IHarvester.sol";

/// @title BaseClaimableStrategy
/// @author Bank of Chain Protocol Inc
abstract contract BaseClaimableStrategy is BaseStrategy, IClaimableStrategy {
    /// @inheritdoc BaseStrategy
    // function harvest()
    //     public
    //     virtual
    //     override
    //     returns (address[] memory _rewardsTokens, uint256[] memory _claimAmounts)
    // {
    //     (_rewardsTokens, _claimAmounts) = claimRewards();
    //     // transfer reward token to harvester
    //     transferTokensToTarget(harvester, _rewardsTokens, _claimAmounts);
    //     vault.report(_rewardsTokens, _claimAmounts);
    // }

    /// @dev Modifier that checks that msg.sender is the vault or not
    modifier onlyHarvester() {
        require(msg.sender == harvester);
        _;
    }

    // /// @notice Collect the rewards from 3rd protocol
    // /// @return _rewardsTokens The list of the reward token
    // /// @return _claimAmounts The list of the reward amount claimed
    // function claimRewards()
    //     internal
    //     virtual
    //     returns (address[] memory _rewardsTokens, uint256[] memory _claimAmounts);

    /// @inheritdoc BaseStrategy
    function repay(
        uint256 _repayShares,
        uint256 _totalShares,
        uint256 _outputCode
    ) public virtual override onlyVault returns (address[] memory _assets, uint256[] memory _amounts) {
        // if withdraw all need claim rewards
        if (_repayShares == _totalShares) {
            IHarvester(harvester).strategyRedeemCollect(address(vault));
        }
        return super.repay(_repayShares, _totalShares, _outputCode);
    }

    /// @notice Transfer rewardToken to Harvester
    /// @return _rewardTokens The address list of the reward token
    /// @return _rewardAmounts The amount list of the reward token
    /// @return _sellTo The address of target token,sell to wants radios when _sellTo is null
    /// @return _needReInvest The sellTo Token is need reInvest to the strategy
    function collectReward()
        external
        onlyHarvester
        returns (
            address[] memory _rewardTokens,
            uint256[] memory _rewardAmounts,
            address _sellTo,
            bool _needReInvest
        )
    {
        (_rewardTokens, _rewardAmounts) = claim();
        _sellTo = sellTo();
        _needReInvest = needReInvest();
        transferTokensToTarget(harvester, _rewardTokens, _rewardAmounts);
    }

    function claim()
        public
        virtual
        returns (address[] memory _rewardTokens, uint256[] memory _rewardAmounts);

    function sellTo() internal virtual returns (address _sellTo){
        return wants[0];
    }

    function needReInvest() internal virtual returns (bool _needReInvest){
        return true;
    }

    function exchangeFinishCallback(uint256 _amount) external onlyHarvester {
        if (_amount > 1) {
            reInvest();
        }
        vault.report();
    }

    function reInvest() internal virtual {
        address[] memory _wantsCopy = wants;
        address[] memory _assets = new address[](_wantsCopy.length);
        uint256[] memory _amounts = new uint256[](_wantsCopy.length);
        for (uint8 i = 0; i < _wantsCopy.length; i++) {
            address _want = _wantsCopy[i];
            uint256 _tokenBalance = balanceOfToken(_want);
            _assets[i] = _want;
            _amounts[i] = _tokenBalance;
        }
        depositTo3rdPool(_assets, _amounts);
    }
}
