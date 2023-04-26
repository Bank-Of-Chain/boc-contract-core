// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../Constants.sol";
import "../../mock/MockExchangeRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockExchangeRouterTest is Test {
    using SafeERC20 for IERC20;

    MockExchangeRouter mockExchangeRouter;
    address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        mockExchangeRouter = new MockExchangeRouter(0xE4153088577C2D634CB4b3451Aa4ab7E7281ef1f);
    }

    function test_swap() public {
        deal(USDT,USER,1e10);
        deal(USDC,address(mockExchangeRouter),1e11);

        uint _fromAmount = 1e8;
        bytes memory swapCalldata = mockExchangeRouter.getCalldata(USDT,USDC,_fromAmount,USER);
        vm.startPrank(USER);
        IERC20(USDT).safeApprove(address(mockExchangeRouter),0);
        IERC20(USDT).safeApprove(address(mockExchangeRouter),_fromAmount);
        (bool _succ,bytes memory _result) = address(mockExchangeRouter).call(swapCalldata);
        vm.stopPrank();
        console.log("_succ:",_succ);

        uint receiveAmount = IERC20(USDC).balanceOf(USER);
        uint _resultDecode = abi.decode(_result,(uint));
        assertEq(receiveAmount,_resultDecode,"receive amount correct");
        assertEq(_fromAmount,1e10 - IERC20(USDT).balanceOf(USER),"user from token should be decreas");
    }
}
