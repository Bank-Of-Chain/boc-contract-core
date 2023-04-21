// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../../access-control/AccessControlProxy.sol";
import "../../price-feeds/ValueInterpreter.sol";
import "../../price-feeds/primitives/ChainlinkPriceFeed.sol";
import "../../price-feeds/primitives/IPrimitivePriceFeed.sol";
import "../../price-feeds/primitives/UniswapV3PriceFeed.sol";
import "../../price-feeds/custom/CustomWstEthPriceFeed.sol";
import "../../price-feeds/custom/CustomEthPriceFeed.sol";
import "../../price-feeds/custom/CustomFakePriceFeed.sol";
import "../../price-feeds/custom/CustomFrxEthPriceFeed.sol";
import "../../price-feeds/custom/CustomSfrxEthPriceFeed.sol";
import "../../price-feeds/custom/CustomSEthPriceFeed.sol";
import "../../price-feeds/custom/CustomPriceFeedAggregator.sol";
import "../Constants.sol";

contract ValueInterpreterTest is Test {
    address constant ETH_USD_AGGREGATOR = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant CBETH_ADDRESS = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant STETH_AGGREAGTOR_ADDRESS = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant CBETH_AGGREAGTOR_ADDRESS = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address constant RETH_AGGREAGTOR_ADDRESS = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address constant ROCKET_ETH_ADDRESS = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant ROCKET_ETH_WETH_POOL_ADDRESS = 0xa4e0faA58465A2D369aa21B3e42d43374c6F9613;

    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant SETH2_ADDRESS = 0xFe2e637202056d30016725477c5da089Ab0A043A;
    address constant SETH2_WETH_POOL_ADDRESS = 0x7379e81228514a1D2a6Cf7559203998E20598346;
    address constant FRX_ETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant SFRX_ETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant S_ETH = 0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb;

    address constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant FAKE_TOKEN_ADDRESS = 0x3F9F6ca28f711B82421A45d3e8a3B73Bd295922B;
    // address constant SETH2_WETH_POOL_ADDRESS = 0xDADcF64BAbfb566785f1e9DFC4889C5e593DDdC7;

    uint256 constant ONE_DAY_HEARTBEAT = 24 hours;
    uint32 constant ROCKET_ETH_DURATION = 1 hours;
    uint32 constant SETH2_DURATION = 1 hours;
    IPrimitivePriceFeed.RateAsset constant STETH_RATE_ASSET = IPrimitivePriceFeed.RateAsset.ETH; //eth

    AccessControlProxy accessControlProxy;
    ValueInterpreter valueInterpreter;
    ChainlinkPriceFeed chainlinkPriceFeed;
    UniswapV3PriceFeed uniswapV3PriceFeed;
    CustomPriceFeedAggregator customPriceFeedAggregator;
    CustomWstEthPriceFeed customWstEthPriceFeed;
    CustomEthPriceFeed customEthPriceFeed;
    CustomFakePriceFeed customFakePriceFeed;
    CustomFrxEthPriceFeed customFrxEthPriceFeed;
    CustomSfrxEthPriceFeed customSfrxEthPriceFeed;
    CustomSEthPriceFeed customSEthPriceFeed;

    uint[] public arr2 = [1, 2, 3];
    uint256 constant PRICE_UPPER = 12 * 1e17;
    uint256 constant PRICE_LOWER = 8 * 1e17;

    function setUp() public {
        console2.log("========ValueInterpreterTest========");

        accessControlProxy = new AccessControlProxy();
        accessControlProxy.initialize(GOVERNANOR, DEGEGATOR, VAULT_MANAGER, KEEPER);

        vm.startPrank(GOVERNANOR);
        address[] memory _primitives = new address[](3);
        _primitives[0] = STETH_ADDRESS;
        _primitives[1] = ROCKET_ETH_ADDRESS;
        _primitives[2] = CBETH_ADDRESS;

        address[] memory _aggregators = new address[](3);
        _aggregators[0] = STETH_AGGREAGTOR_ADDRESS;
        _aggregators[1] = RETH_AGGREAGTOR_ADDRESS;
        _aggregators[2] = CBETH_AGGREAGTOR_ADDRESS;

        uint256[] memory _heartbeats = new uint256[](3);
        _heartbeats[0] = ONE_DAY_HEARTBEAT;
        _heartbeats[1] = ONE_DAY_HEARTBEAT;
        _heartbeats[2] = ONE_DAY_HEARTBEAT;

        IPrimitivePriceFeed.RateAsset[] memory _rateAssets = new IPrimitivePriceFeed.RateAsset[](3);
        _rateAssets[0] = IPrimitivePriceFeed.RateAsset.ETH;
        _rateAssets[1] = IPrimitivePriceFeed.RateAsset.ETH;
        _rateAssets[2] = IPrimitivePriceFeed.RateAsset.ETH;

        address[] memory _basePeggeds = new address[](1);
        _basePeggeds[0] = WETH_ADDRESS;
        IPrimitivePriceFeed.RateAsset[] memory _peggedRateAssets = new IPrimitivePriceFeed.RateAsset[](1);
        _peggedRateAssets[0] = IPrimitivePriceFeed.RateAsset.ETH;

        chainlinkPriceFeed = new ChainlinkPriceFeed(
            ETH_USD_AGGREGATOR,
            ONE_DAY_HEARTBEAT,
            _primitives,
            _aggregators,
            _heartbeats,
            _rateAssets,
            _basePeggeds,
            _peggedRateAssets,
            address(accessControlProxy)
        );

        vm.label(address(chainlinkPriceFeed), "chainlinkPriceFeed");

        address[] memory _primitives2 = new address[](1);
        _primitives2[0] = SETH2_ADDRESS;

        address[] memory _pools = new address[](1);
        _pools[0] = SETH2_WETH_POOL_ADDRESS;

        uint32[] memory _durations = new uint32[](1);
        _durations[0] = SETH2_DURATION;


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
        customFrxEthPriceFeed = new CustomFrxEthPriceFeed();
        vm.label(address(customFrxEthPriceFeed), "customFrxEthPriceFeed");
        customSfrxEthPriceFeed = new CustomSfrxEthPriceFeed();
        vm.label(address(customSfrxEthPriceFeed), "customSfrxEthPriceFeed");
        customSEthPriceFeed = new CustomSEthPriceFeed();
        vm.label(address(customSEthPriceFeed), "customSEthPriceFeed");

        address[] memory _baseAssets = new address[](6);
        _baseAssets[0] = WSTETH;
        _baseAssets[1] = NATIVE_TOKEN_ADDRESS;
        _baseAssets[2] = FAKE_TOKEN_ADDRESS;
        _baseAssets[3] = FRX_ETH;
        _baseAssets[4] = SFRX_ETH;
        _baseAssets[5] = S_ETH;
        address[] memory _customPriceFeeds = new address[](6);
        _customPriceFeeds[0] = address(customWstEthPriceFeed);
        _customPriceFeeds[1] = address(customEthPriceFeed);
        _customPriceFeeds[2] = address(customFakePriceFeed);
        _customPriceFeeds[3] = address(customFrxEthPriceFeed);
        _customPriceFeeds[4] = address(customSfrxEthPriceFeed);
        _customPriceFeeds[5] = address(customSEthPriceFeed);
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
        vm.stopPrank();
    }

    function testQueryAssetPriceInUsd() public {
        uint256 stEthPriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(STETH_ADDRESS, 1 ether);
        console2.log("stEthPriceInUsd:", stEthPriceInUsd);
        uint256 ethPriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(NATIVE_TOKEN_ADDRESS, 1 ether);
        assertGt(stEthPriceInUsd, PRICE_LOWER * ethPriceInUsd/1e18, "price in usd lte PRICE_LOWER");
        assertLt(stEthPriceInUsd, PRICE_UPPER * ethPriceInUsd/1e18, "price in usd gte PRICE_UPPER");
    }

    function testQueryAssetPriceInEth() public {
        uint256 stEthPriceInEth = valueInterpreter.calcCanonicalAssetValueInEth(STETH_ADDRESS, 1 ether);
        console2.log("stEthPriceInEth:", stEthPriceInEth);
        assertGt(stEthPriceInEth, PRICE_LOWER, "price in eth lte PRICE_LOWER");
        assertLt(stEthPriceInEth, PRICE_UPPER, "price in eth gte PRICE_UPPER");
    }

    function testUniswapV3PriceFeed() public {

        uint256 sEth2PriceInEth = valueInterpreter.calcCanonicalAssetValueInEth(SETH2_ADDRESS, 1 ether);
        console2.log("sEth2PriceInEth:", sEth2PriceInEth);

        uint256 sEth2PriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(SETH2_ADDRESS, 1 ether);
        console2.log("sEth2PriceInUsd:", sEth2PriceInUsd);

        uint256 ethPriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(NATIVE_TOKEN_ADDRESS, 1 ether);

        assertGt(sEth2PriceInEth, PRICE_LOWER, "price in eth lte PRICE_LOWER");
        assertLt(sEth2PriceInEth, PRICE_UPPER, "price in eth gte PRICE_UPPER");

        assertGt(sEth2PriceInUsd, PRICE_LOWER * ethPriceInUsd/1e18, "price in usd lte PRICE_LOWER");
        assertLt(sEth2PriceInUsd, PRICE_UPPER * ethPriceInUsd/1e18, "price in usd gte PRICE_UPPER");
    }

    function testCustomWstEthPriceFeed() public {
        uint valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(WSTETH, 1e18);
        console2.log("wstEth valueInEth:", valueInEth);
        uint valueInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(WSTETH, 1e18);
        console2.log("wstEth valueInUsd:", valueInUsd);

        uint256 ethPriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(NATIVE_TOKEN_ADDRESS, 1 ether);

        assertGt(valueInEth, PRICE_LOWER, "price in eth lte PRICE_LOWER");
        assertLt(valueInEth, PRICE_UPPER, "price in eth gte PRICE_UPPER");

        assertGt(valueInUsd, PRICE_LOWER * ethPriceInUsd/1e18, "price in usd lte PRICE_LOWER");
        assertLt(valueInUsd, PRICE_UPPER * ethPriceInUsd/1e18, "price in usd gte PRICE_UPPER");

        vm.prank(GOVERNANOR);
        customPriceFeedAggregator.removeCustomPriceFeed(WSTETH);
        vm.expectRevert();
        valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(WSTETH, 1e18);

        vm.prank(GOVERNANOR);
        customPriceFeedAggregator.addOrReplaceCustomPriceFeed(WSTETH, address(customWstEthPriceFeed));
        valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(WSTETH, 1e18);
    }

    function testCustomSEthPriceFeed() public {
        uint valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(S_ETH, 1e18);
        console2.log("sEth valueInEth:", valueInEth);
        uint valueInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(S_ETH, 1e18);
        console2.log("sEth valueInUsd:", valueInUsd);

        uint256 ethPriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(NATIVE_TOKEN_ADDRESS, 1 ether);

        assertGt(valueInEth, PRICE_LOWER, "price in eth lte PRICE_LOWER");
        assertLt(valueInEth, PRICE_UPPER, "price in eth gte PRICE_UPPER");

        assertGt(valueInUsd, PRICE_LOWER * ethPriceInUsd/1e18, "price in usd lte PRICE_LOWER");
        assertLt(valueInUsd, PRICE_UPPER * ethPriceInUsd/1e18, "price in usd gte PRICE_UPPER");

        vm.prank(GOVERNANOR);
        customPriceFeedAggregator.removeCustomPriceFeed(S_ETH);
        vm.expectRevert();
        valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(S_ETH, 1e18);

        vm.prank(GOVERNANOR);
        customPriceFeedAggregator.addOrReplaceCustomPriceFeed(S_ETH, address(customSEthPriceFeed));
        valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(S_ETH, 1e18);
    }

    function testCustomFrxEthPriceFeed() public {
        uint valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(FRX_ETH, 1e18);
        console2.log("frxEth valueInEth:", valueInEth);
        uint valueInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(FRX_ETH, 1e18);
        console2.log("frxEth valueInUsd:", valueInUsd);

        uint256 ethPriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(NATIVE_TOKEN_ADDRESS, 1 ether);

        assertGt(valueInEth, PRICE_LOWER, "price in eth lte PRICE_LOWER");
        assertLt(valueInEth, PRICE_UPPER, "price in eth gte PRICE_UPPER");

        assertGt(valueInUsd, PRICE_LOWER * ethPriceInUsd/1e18, "price in usd lte PRICE_LOWER");
        assertLt(valueInUsd, PRICE_UPPER * ethPriceInUsd/1e18, "price in usd gte PRICE_UPPER");

        vm.prank(GOVERNANOR);
        customPriceFeedAggregator.removeCustomPriceFeed(FRX_ETH);
        vm.expectRevert();
        valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(FRX_ETH, 1e18);

        vm.prank(GOVERNANOR);
        customPriceFeedAggregator.addOrReplaceCustomPriceFeed(FRX_ETH, address(customFrxEthPriceFeed));
        valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(FRX_ETH, 1e18);
    }

    function testCustomSfrxEthPriceFeed() public {
        uint valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(SFRX_ETH, 1e18);
        console2.log("sfrxEth valueInEth:", valueInEth);
        uint valueInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(SFRX_ETH, 1e18);
        console2.log("sfrxEth valueInUsd:", valueInUsd);

        uint256 ethPriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(NATIVE_TOKEN_ADDRESS, 1 ether);

        assertGt(valueInEth, PRICE_LOWER, "price in eth lte PRICE_LOWER");
        assertLt(valueInEth, PRICE_UPPER, "price in eth gte PRICE_UPPER");

        assertGt(valueInUsd, PRICE_LOWER * ethPriceInUsd/1e18, "price in usd lte PRICE_LOWER");
        assertLt(valueInUsd, PRICE_UPPER * ethPriceInUsd/1e18, "price in usd gte PRICE_UPPER");

        vm.prank(GOVERNANOR);
        customPriceFeedAggregator.removeCustomPriceFeed(SFRX_ETH);
        vm.expectRevert();
        valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(SFRX_ETH, 1e18);

        vm.prank(GOVERNANOR);
        customPriceFeedAggregator.addOrReplaceCustomPriceFeed(SFRX_ETH, address(customSfrxEthPriceFeed));
        valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(SFRX_ETH, 1e18);
    }

    function testQueryEthPrice() public {
        uint valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(NATIVE_TOKEN_ADDRESS, 1e18);
        console2.log("native token valueInEth:", valueInEth);
        uint valueInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(NATIVE_TOKEN_ADDRESS, 1e18);
        console2.log("native token valueInUsd:", valueInUsd);
    }
}
