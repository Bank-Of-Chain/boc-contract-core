// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.8.0 <0.9.0;

import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol';

interface IEREC20Mint is IERC20MetadataUpgradeable {
    function getOwner() external view returns (address);

    function supplyController() external view returns (address);

    function troveManagerAddress() external view returns (address);

    // https://cn.etherscan.com/address/0xdac17f958d2ee523a2206206994597c13d831ec7#writeContract
    function issue(uint256 amount) external;

    // https://cn.etherscan.com/address/0x6b175474e89094c44da98b954eedeac495271d0f#readContract
    function owner() external view returns (address);

    function mint(address _to, uint256 amount) external;

    function increaseSupply(uint256 amount) external;
}
