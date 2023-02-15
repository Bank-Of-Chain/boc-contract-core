// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "../vault/IVault.sol";

/// @title IStrategy interface
interface IStrategy {
    /// @param _outputCode The code of output,0:default path, Greater than 0:specify output path
    /// @param outputTokens The output tokens
    struct OutputInfo {
        uint256 outputCode;
        address[] outputTokens;
    }

    /// @param _assets The address list of tokens borrowing
    /// @param _amounts The amount list of tokens borrowing
    event Borrow(address[] _assets, uint256[] _amounts);

    /// @param _withdrawShares The amount of shares to withdraw. Numerator
    /// @param _totalShares The total amount of shares owned by the strategy. Denominator
    /// @param _assets The address list of the assets repaying
    /// @param _amounts The amount list of the assets repaying
    event Repay(uint256 _withdrawShares, uint256 _totalShares, address[] _assets, uint256[] _amounts);

    /// @param _oldValue the old value of `isWantRatioIgnorable` flag
    /// @param _newValue the new value of `isWantRatioIgnorable` flag
    event SetIsWantRatioIgnorable(bool _oldValue, bool _newValue);

    /// @notice Return the version of strategy
    function getVersion() external pure returns (string memory);

    /// @notice Return the name of strategy
    function name() external view returns (string memory);

    /// @notice Return the ID of strategy
    function protocol() external view returns (uint16);

    /// @notice Return the vault address
    function vault() external view returns (IVault);

    /// @notice Return the harvester address
    function harvester() external view returns (address);

    /// @notice Return the underlying token list and ratio list needed by the strategy
    /// @return _assets the address list of token to deposit
    /// @return _ratios the ratios list of `_assets`.
    ///     The ratio is the proportion of each asset to total assets
    function getWantsInfo() external view returns (address[] memory _assets, uint256[] memory _ratios);

    /// @notice Return the underlying token list needed by the strategy
    function getWants() external view returns (address[] memory _wants);

    /// @notice Return the output path list of the strategy when withdraw.
    function getOutputsInfo() external view returns (OutputInfo[] memory _outputsInfo);

    /// @notice Sets the flag of `isWantRatioIgnorable`
    /// @param _isWantRatioIgnorable "true" means that can ignore ratios given by wants info,
    ///    "false" is the opposite.
    function setIsWantRatioIgnorable(bool _isWantRatioIgnorable) external;

    /// @notice Returns the position details of the strategy.
    /// @return _tokens The list of the position token
    /// @return _amounts The list of the position amount
    /// @return _isUsdOrEth Whether to count in USD(USDi)/ETH(ETHi)
    /// @return _usdOrEthValue The USD(USDi)/ETH(ETHi) value of positions held
    function getPositionDetail()
        external
        view
        returns (
            address[] memory _tokens,
            uint256[] memory _amounts,
            bool _isUsdOrEth,
            uint256 _usdOrEthValue
        );

    /// @notice Return the total assets of strategy in USD(USDi)/ETH(ETHi).
    function estimatedTotalAssets() external view returns (uint256);

    /// @notice Return the third party protocol's pool total assets in USD(USDi)/ETH(ETHi).
    function get3rdPoolAssets() external view returns (uint256);

    /// @notice Sync debt to vault
    function reportToVault() external;

    /// @notice Strategy borrow funds from vault
    ///     enable payable because it needs to receive ETH from vault
    /// @param _assets borrow token address
    /// @param _amounts borrow token amount
    function borrow(address[] memory _assets, uint256[] memory _amounts) external payable;

    /// @notice Strategy repay the funds to vault
    /// @param _withdrawShares The amount of shares to withdraw
    /// @param _totalShares The total amount of shares owned by this strategy
    /// @param _outputCode The code of output
    /// @return _assets The address list of the assets repaying
    /// @return _amounts The amount list of the assets repaying
    function repay(
        uint256 _withdrawShares,
        uint256 _totalShares,
        uint256 _outputCode
    ) external returns (address[] memory _assets, uint256[] memory _amounts);

    /// @notice Return the boolean value of `isWantRatioIgnorable`
    function isWantRatioIgnorable() external view returns (bool);

    /// @notice Return the investable amount of strategy in USD(USDi)/ETH(ETHi)
    function poolDepositQuota() external view returns (uint256);

    /// @notice Return the avaiable withdraw amount of strategy in USD(USDi)/ETH(ETHi)
    function poolWithdrawQuota() external view returns (uint256);


}
