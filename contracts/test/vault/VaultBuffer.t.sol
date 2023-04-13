// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "brain-forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../access-control/AccessControlProxy.sol";
import "../../library/NativeToken.sol";
import "../../vault/IVault.sol";
import "../../harvester/Harvester.sol";
import "../../treasury/Treasury.sol";
import "../Constants.sol";

import "../../vault/VaultBuffer.sol";
import "../../token/PegToken.sol";

contract VaultBufferTest is Test {
    PegToken pegToken;
    VaultBuffer vaultBuffer;

    function setUp() public {
        AccessControlProxy accessControlProxy = new AccessControlProxy();
        accessControlProxy.initialize(GOVERNANOR, DEGEGATOR, VAULT_MANAGER, KEEPER);
        pegToken = new PegToken();
        pegToken.initialize("PegToken", "P", 18, address(this), address(accessControlProxy));

        vaultBuffer = new VaultBuffer();
        vaultBuffer.initialize(
            "Ticket",
            "T",
            address(this),
            address(pegToken),
            address(accessControlProxy)
        );
    }

    function testSetDistributeLimit(uint256 _limit) public {
        _limit = bound(_limit, 1, 1e4);
        vm.prank(VAULT_MANAGER);
        vaultBuffer.setDistributeLimit(_limit);

        assertEq(vaultBuffer.getDistributeLimit(), _limit);
    }

    function testMint(uint256 _shares) public {
        vaultBuffer.mint(USER, _shares);

        assertEq(vaultBuffer.balanceOf(USER), _shares);
    }

    function testTransferCashToVault(uint _usdtAmount, uint _usdcAmount, uint _daiAmount) public {
        address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        // top up for VaultBuffer
        deal(USDT, address(vaultBuffer), _usdtAmount);
        deal(USDC, address(vaultBuffer), _usdcAmount);
        deal(DAI, address(vaultBuffer), _daiAmount);

        address[] memory _assets = new address[](3);
        _assets[0] = USDT;
        _assets[1] = USDC;
        _assets[2] = DAI;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _usdtAmount;
        _amounts[1] = _usdcAmount;
        _amounts[2] = _daiAmount;
        vaultBuffer.transferCashToVault(_assets, _amounts);

        assertEq(IERC20(USDT).balanceOf(address(this)), _usdtAmount);
        assertEq(IERC20(USDC).balanceOf(address(this)), _usdcAmount);
        assertEq(IERC20(DAI).balanceOf(address(this)), _daiAmount);
    }

    function testDistribute() public {
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(IVault.underlyingUnitsPerShare.selector),
            abi.encode(1e18)
        );
        uint underlyingUnitsPerShare = IVault(address(this)).underlyingUnitsPerShare();
        console.log("underlyingUnitsPerShare:",underlyingUnitsPerShare);
        // uint pegTokenAmount = 10000;
        // deal(address(pegToken), address(vaultBuffer), pegTokenAmount);

        // vaultBuffer.openDistribute();
        // assert(vaultBuffer.isDistributing());
    }
}
