// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../access-control/AccessControlProxy.sol";
import "../../price-feeds/ValueInterpreter.sol";
import "../../price-feeds/primitives/ChainlinkPriceFeed.sol";
import "../../price-feeds/primitives/UniswapV3PriceFeed.sol";
import "../../price-feeds/custom/CustomWstEthPriceFeed.sol";
import "../../price-feeds/custom/CustomEthPriceFeed.sol";
import "../../price-feeds/custom/CustomFakePriceFeed.sol";
import "../../price-feeds/custom/CustomPriceFeedAggregator.sol";

import "../../treasury/Treasury.sol";
import "../../vault/Vault.sol";
import "../../vault/IVault.sol";
import "../../vault/VaultAdmin.sol";
import "../../vault/VaultBuffer.sol";
import "../../token/PegToken.sol";

import "../Constants.sol";
import "../UtilsTest.sol";

contract PegTokenTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    UtilsTest internal utils;
    address payable[] internal users;

    address internal alice;
    address internal bob;

    address constant ETH_USD_AGGREGATOR = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant STETH_AGGREAGTOR_ADDRESS = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant ROCKET_ETH_ADDRESS = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant ROCKET_ETH_WETH_POOL_ADDRESS = 0xa4e0faA58465A2D369aa21B3e42d43374c6F9613;

    address constant CBETH_ADDRESS = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant CBETH_WETH_POOL_ADDRESS = 0x840DEEef2f115Cf50DA625F7368C24af6fE74410;


    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_AGGREAGTOR_ADDRESS = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDT_AGGREAGTOR_ADDRESS = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant DAI_AGGREAGTOR_ADDRESS = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant SETH2_ADDRESS = 0xFe2e637202056d30016725477c5da089Ab0A043A;
    address constant SETH2_WETH_POOL_ADDRESS = 0x7379e81228514a1D2a6Cf7559203998E20598346;

    address constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; 
    address constant FAKE_TOKEN_ADDRESS = 0x3F9F6ca28f711B82421A45d3e8a3B73Bd295922B;
    // address constant SETH2_WETH_POOL_ADDRESS = 0xDADcF64BAbfb566785f1e9DFC4889C5e593DDdC7;
    uint256 constant HOURS_OF_24_HEARTBEAT = 24 hours;
    uint256 constant HOURS_OF_1_HEARTBEAT = 1 hours;
    uint32 constant ROCKET_ETH_DURATION = 1 hours;
    uint32 constant SETH2_DURATION = 1 hours;
    uint32 constant CBETH_DURATION = 1 hours;
    IPrimitivePriceFeed.RateAsset constant STETH_RATE_ASSET = IPrimitivePriceFeed.RateAsset.ETH; //eth

    AccessControlProxy accessControlProxy;
    ValueInterpreter valueInterpreter;
    ChainlinkPriceFeed chainlinkPriceFeed;
    UniswapV3PriceFeed uniswapV3PriceFeed;
    CustomPriceFeedAggregator customPriceFeedAggregator;
    CustomWstEthPriceFeed customWstEthPriceFeed;
    CustomEthPriceFeed customEthPriceFeed;
    CustomFakePriceFeed customFakePriceFeed;
    Treasury treasury;
    Vault vault;
    Vault ethVault;
    IVault iETHVault;
    IVault iVault;
    VaultAdmin vaultAdmin;
    VaultAdmin ethVaultAdmin;
    VaultBuffer vaultBuffer;
    VaultBuffer ethVaultBuffer;
    PegToken pegToken;

    uint256[] public arr2 = [1, 2, 3];

    function setUp() public {
        console2.log("========PegTokenTest========");

        accessControlProxy = new AccessControlProxy();
        accessControlProxy.initialize(GOVERNANOR, DEGEGATOR, VAULT_MANAGER, KEEPER);

        vm.startPrank(GOVERNANOR);
        address[] memory _primitives = new address[](4);
        _primitives[0] = STETH_ADDRESS;
        _primitives[1] = USDC_ADDRESS;
        _primitives[2] = USDT_ADDRESS;
        _primitives[3] = DAI_ADDRESS;
        address[] memory _aggregators = new address[](4);
        _aggregators[0] = STETH_AGGREAGTOR_ADDRESS;
        _aggregators[1] = USDC_AGGREAGTOR_ADDRESS;
        _aggregators[2] = USDT_AGGREAGTOR_ADDRESS;
        _aggregators[3] = DAI_AGGREAGTOR_ADDRESS;
        uint256[] memory _heartbeats = new uint256[](4);
        _heartbeats[0] = HOURS_OF_24_HEARTBEAT;
        _heartbeats[1] = HOURS_OF_24_HEARTBEAT;
        _heartbeats[2] = HOURS_OF_24_HEARTBEAT;
        _heartbeats[3] = HOURS_OF_1_HEARTBEAT;
        IPrimitivePriceFeed.RateAsset[] memory _rateAssets = new IPrimitivePriceFeed.RateAsset[](4);
        _rateAssets[0] = STETH_RATE_ASSET;
        _rateAssets[1] = IPrimitivePriceFeed.RateAsset.USD;
        _rateAssets[2] = IPrimitivePriceFeed.RateAsset.USD;
        _rateAssets[3] = IPrimitivePriceFeed.RateAsset.USD;
        address[] memory _basePeggeds = new address[](1);
        _basePeggeds[0] = WETH_ADDRESS;
        IPrimitivePriceFeed.RateAsset[] memory _peggedRateAssets = new IPrimitivePriceFeed.RateAsset[](1);
        _peggedRateAssets[0] = STETH_RATE_ASSET;

        chainlinkPriceFeed = new ChainlinkPriceFeed(
            ETH_USD_AGGREGATOR,
            HOURS_OF_24_HEARTBEAT,
            _primitives,
            _aggregators,
            _heartbeats,
            _rateAssets,
            _basePeggeds,
            _peggedRateAssets,
            address(accessControlProxy)
        );

        vm.label(address(chainlinkPriceFeed), "chainlinkPriceFeed");

        address[] memory _primitives2 = new address[](3);
        _primitives2[0] = ROCKET_ETH_ADDRESS;
        _primitives2[1] = SETH2_ADDRESS;
        _primitives2[2] = CBETH_ADDRESS;
        address[] memory _pools = new address[](3);
        _pools[0] = ROCKET_ETH_WETH_POOL_ADDRESS;
        _pools[1] = SETH2_WETH_POOL_ADDRESS;
        _pools[2] = CBETH_WETH_POOL_ADDRESS;
        uint32[] memory _durations = new uint32[](3);
        _durations[0] = ROCKET_ETH_DURATION;
        _durations[1] = SETH2_DURATION;
        _durations[2] = CBETH_DURATION;
        uniswapV3PriceFeed = new UniswapV3PriceFeed(
            address(accessControlProxy),
            ETH_USD_AGGREGATOR,
            _primitives2,
            _pools,
            _durations
        );
        vm.label(address(uniswapV3PriceFeed), "uniswapV3PriceFeed");

        customWstEthPriceFeed = new CustomWstEthPriceFeed();
        vm.label(address(customWstEthPriceFeed), "customWstEthPriceFeed");
        customEthPriceFeed = new CustomEthPriceFeed();
        vm.label(address(customEthPriceFeed), "customEthPriceFeed");
        customFakePriceFeed = new CustomFakePriceFeed();
        vm.label(address(customFakePriceFeed), "customFakePriceFeed");

        address[] memory _baseAssets = new address[](4);
        _baseAssets[0] = WSTETH;
        _baseAssets[1] = NATIVE_TOKEN_ADDRESS;
        _baseAssets[2] = FAKE_TOKEN_ADDRESS;
        _baseAssets[3] = WETH_ADDRESS;
        address[] memory _customPriceFeeds = new address[](4);
        _customPriceFeeds[0] = address(customWstEthPriceFeed);
        _customPriceFeeds[1] = address(customEthPriceFeed);
        _customPriceFeeds[2] = address(customFakePriceFeed);
        _customPriceFeeds[3] = address(customEthPriceFeed);
        customPriceFeedAggregator = new CustomPriceFeedAggregator(
            _baseAssets,
            _customPriceFeeds,
            address(accessControlProxy)
        );

        valueInterpreter = new ValueInterpreter(
            address(chainlinkPriceFeed),
            address(uniswapV3PriceFeed),
            address(customPriceFeedAggregator),
            address(accessControlProxy)
        );
        vm.label(address(valueInterpreter), "valueInterpreter");

        treasury = new Treasury();
        treasury.initialize(address(accessControlProxy));
        vm.label(address(treasury), "treasury");

        // init USDi Vault
        vaultAdmin = new VaultAdmin();
        vm.label(address(vaultAdmin), "vaultAdmin");
        vault = new Vault();
        vault.initialize(
            address(accessControlProxy),
            address(treasury),
            address(valueInterpreter),
            uint256(0)
        );

        vault.setAdminImpl(address(vaultAdmin));

        vm.label(address(vault), "vault");

        pegToken = new PegToken();
        pegToken.initialize(
            "USD Peg Token",
            "USDi",
            uint8(18),
            address(vault),
            address(accessControlProxy)
        );
        vm.label(address(pegToken), "pegToken");

        vaultBuffer = new VaultBuffer();
        vaultBuffer.initialize(
            "USD Peg Token Ticket",
            "tUSDi",
            address(vault),
            address(pegToken),
            address(accessControlProxy)
        );
        vm.label(address(vaultBuffer), "vaultBuffer");

        iVault = IVault(address(vault));

        iVault.setPegTokenAddress(address(pegToken));
        iVault.setVaultBufferAddress(address(vaultBuffer));

        vm.stopPrank();

        utils = new UtilsTest();
        users = utils.createUsers(2);

        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
    }

    function testSymbol() public {
        assertEq(pegToken.symbol(), "USDi", "Symbol is incorrect");
    }

    function testName() public {
        assertEq(pegToken.name(), "USD Peg Token", "Name is incorrect");
    }

    function testDecimals() public {
        assertEq(pegToken.decimals(), 18, "Decimals is incorrect");
    }

    function testMintShares() public {
        uint256 amount = 100e27;
        vm.startPrank(address(vault));
        pegToken.mintShares(alice, amount);
        assertEq(pegToken.balanceOf(alice),amount/1e9);
        assertEq(pegToken.totalSupply(),amount/1e9);

        vm.stopPrank();
    }

    function testTransfer() public {
        testMintShares();
        uint256 amount = 10e18;
        address sender = alice;
        address recipient = address(0x123);

        uint256 initialSenderBalance = pegToken.balanceOf(sender);
        uint256 initialRecipientBalance = pegToken.balanceOf(recipient);

        vm.prank(alice);
        pegToken.transfer(recipient, amount);

        assertEq(pegToken.balanceOf(sender), initialSenderBalance - amount, "Sender balance is incorrect after transfer");
        assertEq(pegToken.balanceOf(recipient), initialRecipientBalance + amount, "Recipient balance is incorrect after transfer");
    }

    function testApprove() public {
        uint256 amount = 10e18;
        address sender = alice;
        address spender = address(0x456);

        vm.prank(alice);
        pegToken.approve(spender, amount);

        assertEq(pegToken.allowance(sender, spender), amount, "Allowance is incorrect after approve");
    }

    function testTransferFrom() public {
        testMintShares();
        uint256 amount = 10e18;
        address sender = alice;
        address recipient = address(0x123);
        address spender = address(0x456);

        uint256 initialSenderBalance = pegToken.balanceOf(sender);
        uint256 initialRecipientBalance = pegToken.balanceOf(recipient);

        vm.prank(alice);
        pegToken.approve(spender, amount);
        deal(spender, 1 ether);
        vm.prank(spender);
        pegToken.transferFrom(sender, recipient, amount);

        assertEq(pegToken.balanceOf(sender), initialSenderBalance - amount, "Sender balance is incorrect after transfer");
        assertEq(pegToken.balanceOf(recipient), initialRecipientBalance + amount, "Recipient balance is incorrect after transfer");

    }

    function testIncreaseAllowance() public {

        testApprove();
        uint256 amount = 10e18;
        address sender = alice;
        address spender = address(0x456);

        vm.prank(sender);
        pegToken.increaseAllowance(spender, amount);

        assertEq(pegToken.allowance(sender, spender), amount * 2, "Allowance is incorrect after increaseAllowance");
    }

    function testDecreaseAllowance() public {
        testApprove();
        uint256 amount = 10e18;
        address sender = alice;
        address spender = address(0x456);

        vm.prank(sender);
        pegToken.decreaseAllowance(spender, amount / 2);

        assertEq(pegToken.allowance(sender, spender), amount / 2, "Allowance is incorrect after decreaseAllowance");
    }

    function testBurnShares() public {
        testMintShares();
        uint256 amount = 100e27;
        uint256 burnAmount = 50e27;
        vm.prank(address(vault));
        pegToken.burnShares(alice, burnAmount);
        assertEq(pegToken.balanceOf(alice),(amount- burnAmount)/1e9);

    }

    function testChangePauseState() public {
        assertEq(pegToken.isPaused(),false);
        vm.prank(GOVERNANOR);
        pegToken.changePauseState(true);
        assertEq(pegToken.isPaused(),true);
    }

    function testFailAfterChangePauseStatetoTrue() public {
        testMintShares();
        testChangePauseState();
        assertEq(pegToken.isPaused(),true);

        // Fail
        testMintShares();
        testBurnShares();
        testTransfer(); 
        testApprove();
        testTransferFrom();
        testIncreaseAllowance();
        testDecreaseAllowance();
    }





}
