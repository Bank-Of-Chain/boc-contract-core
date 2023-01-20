// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "brain-forge-std/Test.sol";

import "../../access-control/AccessControlProxy.sol";
import "../../price-feeds/ValueInterpreter.sol";
import "../../price-feeds/primitives/ChainlinkPriceFeed.sol";
import "../../price-feeds/primitives/UniswapV3PriceFeed.sol";
import "../../price-feeds/custom/CustomWstEthPriceFeed.sol";
import "../../price-feeds/custom/CustomEthPriceFeed.sol";
import "../../price-feeds/custom/CustomFakePriceFeed.sol";
import "../../price-feeds/custom/CustomPriceFeedAggregator.sol";
import "../Constants.sol";

contract ValueInterpreterTest is Test {
    address constant ETH_USD_AGGREGATOR = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant STETH_AGGREAGTOR_ADDRESS = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant ROCKET_ETH_ADDRESS = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant ROCKET_ETH_WETH_POOL_ADDRESS = 0xa4e0faA58465A2D369aa21B3e42d43374c6F9613;

    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant SETH2_ADDRESS = 0xFe2e637202056d30016725477c5da089Ab0A043A;
    address constant SETH2_WETH_POOL_ADDRESS = 0x7379e81228514a1D2a6Cf7559203998E20598346;

    address constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant FAKE_TOKEN_ADDRESS = 0x3F9F6ca28f711B82421A45d3e8a3B73Bd295922B;
    // address constant SETH2_WETH_POOL_ADDRESS = 0xDADcF64BAbfb566785f1e9DFC4889C5e593DDdC7;

    uint256 constant STETH_HEARTBEAT = 24 hours;
    uint32 constant ROCKET_ETH_DURATION = 1 hours;
    uint32 constant SETH2_DURATION = 1 hours;
    ChainlinkPriceFeed.RateAsset constant STETH_RATE_ASSET = ChainlinkPriceFeed.RateAsset.ETH; //eth

    AccessControlProxy accessControlProxy;
    ValueInterpreter valueInterpreter;
    ChainlinkPriceFeed chainlinkPriceFeed;
    UniswapV3PriceFeed uniswapV3PriceFeed;
    CustomPriceFeedAggregator customPriceFeedAggregator;
    CustomWstEthPriceFeed customWstEthPriceFeed;
    CustomEthPriceFeed customEthPriceFeed;
    CustomFakePriceFeed customFakePriceFeed;

    uint[] public arr2 = [1, 2, 3];

    function setUp() public {
        console2.log("========ValueInterpreterTest========");

        accessControlProxy = new AccessControlProxy();
        accessControlProxy.initialize(GOVERNANOR, DEGEGATOR, VAULT_MANAGER, KEEPER);

        vm.startPrank(GOVERNANOR);
        address[] memory _primitives = new address[](1);
        _primitives[0] = STETH_ADDRESS;
        address[] memory _aggregators = new address[](1);
        _aggregators[0] = STETH_AGGREAGTOR_ADDRESS;
        uint256[] memory _heartbeats = new uint256[](1);
        _heartbeats[0] = STETH_HEARTBEAT;
        ChainlinkPriceFeed.RateAsset[] memory _rateAssets = new ChainlinkPriceFeed.RateAsset[](1);
        _rateAssets[0] = STETH_RATE_ASSET;
        address[] memory _basePeggeds = new address[](1);
        _basePeggeds[0] = WETH_ADDRESS;
        ChainlinkPriceFeed.RateAsset[] memory _peggedRateAssets = new ChainlinkPriceFeed.RateAsset[](1);
        _peggedRateAssets[0] = STETH_RATE_ASSET;

        chainlinkPriceFeed = new ChainlinkPriceFeed(
            ETH_USD_AGGREGATOR,
            STETH_HEARTBEAT,
            _primitives,
            _aggregators,
            _heartbeats,
            _rateAssets,
            _basePeggeds,
            _peggedRateAssets,
            address(accessControlProxy)
        );

        vm.label(address(chainlinkPriceFeed), "chainlinkPriceFeed");

        address[] memory _primitives2 = new address[](2);
        _primitives2[0] = ROCKET_ETH_ADDRESS;
        _primitives2[1] = SETH2_ADDRESS;
        address[] memory _pools = new address[](2);
        _pools[0] = ROCKET_ETH_WETH_POOL_ADDRESS;
        _pools[1] = SETH2_WETH_POOL_ADDRESS;
        uint32[] memory _durations = new uint32[](2);
        _durations[0] = ROCKET_ETH_DURATION;
        _durations[1] = SETH2_DURATION;
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

        address[] memory _baseAssets = new address[](3);
        _baseAssets[0] = WSTETH;
        _baseAssets[1] = NATIVE_TOKEN_ADDRESS;
        _baseAssets[2] = FAKE_TOKEN_ADDRESS;
        address[] memory _customPriceFeeds = new address[](3);
        _customPriceFeeds[0] = address(customWstEthPriceFeed);
        _customPriceFeeds[1] = address(customEthPriceFeed);
        _customPriceFeeds[2] = address(customFakePriceFeed);
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

    function testQueryAssetPriceInUsd() public view {
        uint256 stEthPriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(STETH_ADDRESS, 1 ether);
        console2.log("stEthPriceInUsd:", stEthPriceInUsd);
    }

    function testQueryAssetPriceInEth() public view {
        uint256 stEthPriceInEth = valueInterpreter.calcCanonicalAssetValueInEth(STETH_ADDRESS, 1 ether);
        console2.log("stEthPriceInEth:", stEthPriceInEth);
    }

    function testUniswapV3PriceFeed() public view {
        uint256 rEthPriceInEth = valueInterpreter.calcCanonicalAssetValueInEth(
            ROCKET_ETH_ADDRESS,
            1 ether
        );
        console2.log("rEthPriceInEth:", rEthPriceInEth);

        uint256 rEthPriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(
            ROCKET_ETH_ADDRESS,
            1 ether
        );
        console2.log("rEthPriceInUsd:", rEthPriceInUsd);

        uint256 sEth2PriceInEth = valueInterpreter.calcCanonicalAssetValueInEth(SETH2_ADDRESS, 1 ether);
        console2.log("sEth2PriceInEth:", sEth2PriceInEth);

        uint256 sEth2PriceInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(SETH2_ADDRESS, 1 ether);
        console2.log("sEth2PriceInUsd:", sEth2PriceInUsd);

        uint256 rEthToSEth2 = valueInterpreter.calcCanonicalAssetValue(
            ROCKET_ETH_ADDRESS,
            1 ether,
            SETH2_ADDRESS
        );
        console2.log("rEthToSEth2:", rEthToSEth2);

        uint256 sEth2ToREth = valueInterpreter.calcCanonicalAssetValue(
            SETH2_ADDRESS,
            1 ether,
            ROCKET_ETH_ADDRESS
        );
        console2.log("sEth2ToREth:", sEth2ToREth);
    }

    function testCustomWstEthPriceFeed() public {
        uint valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(WSTETH, 1e18);
        console2.log("wstEth valueInEth:", valueInEth);
        uint valueInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(WSTETH, 1e18);
        console2.log("wstEth valueInUsd:", valueInUsd);

        vm.prank(GOVERNANOR);
        customPriceFeedAggregator.removeCustomPriceFeed(WSTETH);
        vm.expectRevert();
        valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(WSTETH, 1e18);

        vm.prank(GOVERNANOR);
        customPriceFeedAggregator.addOrReplaceCustomPriceFeed(WSTETH, address(customWstEthPriceFeed));
        valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(WSTETH, 1e18);
    }

    function testCustomPriceFeedAggregator_calcCanonicalValue() public {
        (uint256 _wstEthValueInUsd, ) = customPriceFeedAggregator.calcValueInUsd(WSTETH, 1e18);
        (uint256 _fakeTokenValueInUsd, ) = customPriceFeedAggregator.calcValueInUsd(
            FAKE_TOKEN_ADDRESS,
            1e18
        );
        console2.log(
            "_wstEthValueInUsd:%s,_fakeTokenValueInUsd:%s",
            _wstEthValueInUsd,
            _fakeTokenValueInUsd
        );
        (uint256 _quoteAssetAmount, ) = customPriceFeedAggregator.calcCanonicalValue(
            WSTETH,
            1e18,
            FAKE_TOKEN_ADDRESS
        );
        console2.log("_quoteAssetAmount:", _quoteAssetAmount);
    }

    function testQueryEthPrice() public {
        uint valueInEth = valueInterpreter.calcCanonicalAssetValueInEth(NATIVE_TOKEN_ADDRESS, 1e18);
        console2.log("native token valueInEth:", valueInEth);
        uint valueInUsd = valueInterpreter.calcCanonicalAssetValueInUsd(NATIVE_TOKEN_ADDRESS, 1e18);
        console2.log("native token valueInUsd:", valueInUsd);
    }
}
