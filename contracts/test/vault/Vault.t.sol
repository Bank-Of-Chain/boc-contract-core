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
import "../../mock/Mock3CoinStrategy.sol";
import "../../harvester/Harvester.sol";
import "../../library/NativeToken.sol";
import "../../mock/IEREC20Mint.sol";

import "../Constants.sol";

contract VaultTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;

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

    bytes txData1 = hex"e449022e0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000391c1cb6ba5562ab100000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000060594a405d53811d3bc4766596efd80fd545a270cfee7c08";
    // copy from https://cn.etherscan.com/tx/0xa8a80056e01222e2608781dedca8988c22a5f2ea6a7867a87f55fba832c66df3
    bytes txData2 = hex"0b86a4c1000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000003dae3c788199a8fb62000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000001000000000000000000004de494b86ca6f7a495930fe7f552eb9e4cbb5ef2b736";

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
    Treasury treasury02;
    Vault vault;
    Vault ethVault;
    IVault iETHVault;
    IVault iVault;
    VaultAdmin vaultAdmin;
    VaultAdmin ethVaultAdmin;
    VaultBuffer vaultBuffer;
    VaultBuffer ethVaultBuffer;
    PegToken pegToken;
    PegToken ethPegToken;
    Harvester harvester;
    Harvester ethHarvester;
    Mock3CoinStrategy mock3CoinStrategy;
    Mock3CoinStrategy otherMock3CoinStrategy;
    Mock3CoinStrategy ethMock3CoinStrategy;
    Mock3CoinStrategy otherEthMock3CoinStrategy;

    uint256[] public arr2 = [1, 2, 3];

    function setUp() public {
        console2.log("========VaultTest========");

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

        treasury02 = new Treasury();
        treasury02.initialize(address(accessControlProxy));

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
        iVault.setMinimumInvestmentAmount(10);

        mock3CoinStrategy = new Mock3CoinStrategy();
        address[] memory _wants = new address[](3);
        // USDT
        _wants[0] = USDT_ADDRESS;
        // USDC
        _wants[1] = USDC_ADDRESS;
        // DAI
        _wants[2] = DAI_ADDRESS;
        uint256[] memory _ratios = new uint256[](3);
        _ratios[0] = 1;
        _ratios[1] = 2;
        _ratios[2] = 4;
        mock3CoinStrategy.initialize(address(vault), address(harvester), _wants, _ratios);
        vm.label(address(mock3CoinStrategy), "mock3CoinStrategy");

        otherMock3CoinStrategy = new Mock3CoinStrategy();
        otherMock3CoinStrategy.initialize(address(vault), address(harvester), _wants, _ratios);
        vm.label(address(otherMock3CoinStrategy), "otherMock3CoinStrategy");

        // init ETHi Vault
        ethVaultAdmin = new VaultAdmin();
        vm.label(address(ethVaultAdmin), "ethVaultAdmin");
        ethVault = new Vault();
        ethVault.initialize(
            address(accessControlProxy),
            address(treasury),
            address(valueInterpreter),
            uint256(1)
        );

        ethVault.setAdminImpl(address(ethVaultAdmin));

        vm.label(address(ethVault), "ethVault");

        ethPegToken = new PegToken();
        ethPegToken.initialize(
            "ETH Peg Token",
            "ETHi",
            uint8(18),
            address(ethVault),
            address(accessControlProxy)
        );
        vm.label(address(ethPegToken), "ethPegToken");

        ethVaultBuffer = new VaultBuffer();
        ethVaultBuffer.initialize(
            "ETH Peg Token Ticket",
            "tETHi",
            address(ethVault),
            address(ethPegToken),
            address(accessControlProxy)
        );
        vm.label(address(ethVaultBuffer), "ethVaultBuffer");

        iETHVault = IVault(address(ethVault));

        iETHVault.setPegTokenAddress(address(ethPegToken));
        iETHVault.setVaultBufferAddress(address(ethVaultBuffer));
        iETHVault.setMinimumInvestmentAmount(10);

        harvester = new Harvester();
        harvester.initialize(
            address(accessControlProxy),
            address(treasury),
            address(vault),
            address(iETHVault)
        );
        vm.label(address(harvester), "harvester");

        ethMock3CoinStrategy = new Mock3CoinStrategy();
        address[] memory _ethWants = new address[](3);
        // ETH
        _ethWants[0] = NativeToken.NATIVE_TOKEN;
        // stETH
        _ethWants[1] = STETH_ADDRESS;
        // WETH
        _ethWants[2] = WETH_ADDRESS;
        uint256[] memory _ethRatios = new uint256[](3);
        _ethRatios[0] = 1;
        _ethRatios[1] = 2;
        _ethRatios[2] = 4;
        ethMock3CoinStrategy.initialize(address(ethVault), address(ethHarvester), _ethWants, _ethRatios);
        vm.label(address(ethMock3CoinStrategy), "ethMock3CoinStrategy");

        otherEthMock3CoinStrategy = new Mock3CoinStrategy();
        otherEthMock3CoinStrategy.initialize(address(ethVault), address(ethHarvester), _ethWants, _ethRatios);
        vm.label(address(otherEthMock3CoinStrategy), "otherEthMock3CoinStrategy");

        vm.stopPrank();
    }

    function testSetMethodsOfVaultAdmin() public {
        vm.startPrank(GOVERNANOR);
        assertEq(iVault.emergencyShutdown(),false);
        iVault.setEmergencyShutdown(true);
        assertEq(iVault.emergencyShutdown(),true);

        assertEq(iVault.adjustPositionPeriod(),false);
        iVault.setAdjustPositionPeriod(true);
        assertEq(iVault.adjustPositionPeriod(),true);

        //iVault.deltaThreshold()
        assertEq(iVault.deltaThreshold(),100);
        iVault.setDeltaThreshold(1000);
        assertEq(iVault.deltaThreshold(),1000);

        // setRedeemFeeBps
        assertEq(iVault.redeemFeeBps(),0);
        iVault.setRedeemFeeBps(100);
        assertEq(iVault.redeemFeeBps(),100);

        assertEq(iVault.maxTimestampBetweenTwoReported(),604800);
        iVault.setMaxTimestampBetweenTwoReported(864000);
        assertEq(iVault.maxTimestampBetweenTwoReported(),864000);

        //setMinCheckedStrategyTotalDebt
        assertEq(iVault.minCheckedStrategyTotalDebt(),1000e18);
        iVault.setMinCheckedStrategyTotalDebt(2000e18);
        assertEq(iVault.minCheckedStrategyTotalDebt(),2000e18);

        assertEq(iVault.minimumInvestmentAmount(),10);
        iVault.setMinimumInvestmentAmount(1e19);
        assertEq(iVault.minimumInvestmentAmount(),1e19);

        address _newAddress = address(treasury02);

        assertEq(iVault.treasury(),address(treasury));
        iVault.setTreasuryAddress(address(treasury02));
        assertEq(iVault.treasury(),address(treasury02));

        assertEq(iVault.exchangeManager(),address(0));
        iVault.setExchangeManagerAddress(_newAddress);
        assertEq(iVault.exchangeManager(),_newAddress);

        assertEq(iVault.trusteeFeeBps(),0);
        iVault.setTrusteeFeeBps(1000);
        assertEq(iVault.trusteeFeeBps(),1000);

        assertEq(iVault.rebasePaused(),false);
        iVault.pauseRebase();
        assertEq(iVault.rebasePaused(),true);

        iVault.unpauseRebase();
        assertEq(iVault.rebasePaused(),false);  
    }

    function testAddAndRemoveAssets() public { 
        address[] memory _assets = iVault.getSupportAssets();
        assertEq(_assets.length, 0);

        vm.startPrank(GOVERNANOR);
        iVault.addAsset(USDC_ADDRESS);
        _assets = iVault.getSupportAssets();
        assertEq(_assets.length, 1);

        iVault.removeAsset(USDC_ADDRESS);
        _assets = iVault.getSupportAssets();
        assertEq(_assets.length, 0);

        iVault.addAsset(USDC_ADDRESS);
        iVault.addAsset(USDT_ADDRESS);
        iVault.addAsset(DAI_ADDRESS);
        _assets = iVault.getSupportAssets();
        vm.stopPrank();
        assertEq(_assets.length, 3);
    }

    function testViewMethodsOfAssets() public { 
        string memory version = iVault.getVersion();
        string memory curVersion = "2.0.0";// to be edited if version update
        assertEq(version, curVersion);

        // test muliti methods:getSupportAssets,getTrackedAssets,
        address[] memory _assets = iVault.getSupportAssets();
        assertEq(_assets.length, 0);

        address[] memory _trackedAssets = iVault.getTrackedAssets();
        assertEq(_trackedAssets.length, 0);

        vm.startPrank(GOVERNANOR);
        iVault.addAsset(USDC_ADDRESS);
        _assets = iVault.getSupportAssets();
        assertEq(_assets.length, 1);
        assertEq(_assets[0], USDC_ADDRESS);
        //just check, non return
        iVault.checkIsSupportAsset(USDC_ADDRESS);

        _trackedAssets = iVault.getTrackedAssets();
        assertEq(_trackedAssets.length, 1);
        assertEq(_trackedAssets[0], USDC_ADDRESS);

        iVault.removeAsset(USDC_ADDRESS);
        _assets = iVault.getSupportAssets();
        assertEq(_assets.length, 0);

        _trackedAssets = iVault.getTrackedAssets();
        assertEq(_trackedAssets.length, 0);


        iVault.addAsset(USDC_ADDRESS);
        iVault.addAsset(USDT_ADDRESS);
        iVault.addAsset(DAI_ADDRESS);
        _assets = iVault.getSupportAssets();
        assertEq(_assets[0], USDC_ADDRESS);
        assertEq(_assets[1], USDT_ADDRESS);
        assertEq(_assets[2], DAI_ADDRESS);
        assertEq(_assets.length, 3);

        _trackedAssets = iVault.getTrackedAssets();
        assertEq(_trackedAssets[0], USDC_ADDRESS);
        assertEq(_trackedAssets[1], USDT_ADDRESS);
        assertEq(_trackedAssets[2], DAI_ADDRESS);
        assertEq(_trackedAssets.length, 3);
        assertEq(true, iVault.isTrackedAssets(USDC_ADDRESS));
        assertEq(true, iVault.isTrackedAssets(USDT_ADDRESS));
        assertEq(true, iVault.isTrackedAssets(DAI_ADDRESS));

        vm.stopPrank();
    }

    function testAddAndRemoveAssetsWithETHi() public {
        address[] memory _assets = iETHVault.getSupportAssets();
        assertEq(_assets.length, 0);

        vm.startPrank(GOVERNANOR);
        iETHVault.addAsset(NativeToken.NATIVE_TOKEN);
        _assets = iETHVault.getSupportAssets();
        assertEq(_assets.length, 1);

        iETHVault.removeAsset(NativeToken.NATIVE_TOKEN);
        _assets = iETHVault.getSupportAssets();
        assertEq(_assets.length, 0);

        iETHVault.addAsset(NativeToken.NATIVE_TOKEN);
        iETHVault.addAsset(STETH_ADDRESS);
        iETHVault.addAsset(WETH_ADDRESS);
        _assets = iETHVault.getSupportAssets();
        vm.stopPrank();
        assertEq(_assets.length, 3);
    }

    function calculateLendValue(
        Mock3CoinStrategy  mockStrategy,
        uint256[] memory _ratiosLocal, 
        uint256[] memory _amounts,
        address[] memory _wants,
        address[] memory _tokens,
        ValueInterpreter valueInterpreter,
        uint256 vaultType
    ) private returns(uint256 totalLendAsset){
        (,uint256[] memory _ratiosLocal) = mockStrategy.getWantsInfo();
        uint256 _wantsLength = _wants.length;

        uint256 _minProductIndex;
        bool _isWantRatioIgnorable = mockStrategy.isWantRatioIgnorable();
        if (!_isWantRatioIgnorable && _wantsLength > 1) {
            for (uint256 i = 1; i < _wantsLength; i++) {
                if (_ratiosLocal[i] == 0) {
                    //0 is free
                    continue;
                } else if (_ratiosLocal[_minProductIndex] == 0) {
                    //minProductIndex is assigned to the first index whose proportion is not 0
                    _minProductIndex = i;
                } else if (
                    _amounts[_minProductIndex] * _ratiosLocal[i] > _amounts[i] * _ratiosLocal[_minProductIndex]
                ) {
                    _minProductIndex = i;
                }
            }
        }

        uint256 _minAmount = _amounts[_minProductIndex];
        uint256 _minAspect = _ratiosLocal[_minProductIndex];
        for (uint256 i = 0; i < _wantsLength; i++) {
            uint256 _actualAmount = _amounts[i];
            if (_actualAmount > 0) {
                if (!_isWantRatioIgnorable ) {
                    if (_ratiosLocal[i] > 0) {
                        _actualAmount = (_ratiosLocal[i] * _minAmount) / _minAspect;
                        
                    }else{
                        continue;
                    }
                }
                uint256 value;
                if(vaultType == 0) {
                    value = valueInterpreter.calcCanonicalAssetValueInUsd(_tokens[i],_actualAmount);
                }else {
                    value = valueInterpreter.calcCanonicalAssetValueInEth(_tokens[i],_actualAmount);
                }
                
                totalLendAsset += value;
            }
        }
    }

    function testLend() public{
        vm.startPrank(GOVERNANOR);
        Mock3CoinStrategy  mockStrategy = new Mock3CoinStrategy();
        address[] memory _wants = new address[](3);
        // USDT
        _wants[0] = USDT_ADDRESS;
        // USDC
        _wants[1] = USDC_ADDRESS;
        // DAI
        _wants[2] = DAI_ADDRESS;
        uint256[] memory _ratios = new uint256[](3);
        _ratios[0] = 1;
        _ratios[1] = 2;
        _ratios[2] = 0;
        mockStrategy.initialize(address(vault), address(harvester), _wants, _ratios);

        IVault.StrategyAdd[] memory _strategyAdds = new IVault.StrategyAdd[](2);
        _strategyAdds[0] = IVault.StrategyAdd({
        strategy: address(mockStrategy),
        profitLimitRatio: uint256(100),
        lossLimitRatio: uint256(100),
        targetDebt:uint256(1e24)
        });
        _strategyAdds[1] = IVault.StrategyAdd({
        strategy: address(otherMock3CoinStrategy),
        profitLimitRatio: uint256(100),
        lossLimitRatio: uint256(100),
        targetDebt:uint256(1e24)
        });

        iVault.addStrategies(_strategyAdds);


        uint256 _usdcAmount = 10000e6;
        uint256 _usdtAmount = 10000e6;
        uint256 _daiAmount = 10000e18;
        deal(USDC_ADDRESS, address(vault), _usdcAmount);
        deal(USDT_ADDRESS, address(vault), _usdtAmount);
        deal(DAI_ADDRESS, address(vault), _daiAmount);


        address[] memory _tokens = new address[](3);
        _tokens[0] = USDT_ADDRESS;
        _tokens[1] = USDC_ADDRESS;
        _tokens[2] = DAI_ADDRESS;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _balanceOfToken(USDT_ADDRESS, address(vault));
        _amounts[1] = _balanceOfToken(USDC_ADDRESS, address(vault));
        _amounts[2] = _balanceOfToken(DAI_ADDRESS, address(vault));

        uint256 totalLendAsset = calculateLendValue(
            mockStrategy,
            _ratios,
            _amounts,
            _wants,
            _tokens,
            valueInterpreter,
            0
        );
        console2.log("====totalLendAsset is ===",totalLendAsset);
        uint256 _minDeltaAssets = totalLendAsset;
        uint256 __minDeltaAssets = iVault.lend(address(mockStrategy), _tokens, _amounts,_minDeltaAssets);
        console2.log("====_minDeltaAssets is ===",__minDeltaAssets);

        vm.stopPrank();

        assertGt(mockStrategy.estimatedTotalAssets(),0);

        assertEq(_balanceOfToken(USDT_ADDRESS, address(vault)), _amounts[0]/2);
        assertEq(_balanceOfToken(USDC_ADDRESS, address(vault)), 0);
        assertEq(_balanceOfToken(DAI_ADDRESS, address(vault)), _amounts[2]);
    }

    function testLendWithETHi() public{
        vm.startPrank(GOVERNANOR);
        Mock3CoinStrategy  ethMockStrategy = new Mock3CoinStrategy();

        address[] memory _wants = new address[](3);
        // eth
        _wants[0] = NativeToken.NATIVE_TOKEN;
        // steth
        _wants[1] = STETH_ADDRESS;
        // weth
        _wants[2] = WETH_ADDRESS;
        uint256[] memory _ratios = new uint256[](3);
        _ratios[0] = 1;
        _ratios[1] = 2;
        _ratios[2] = 0;
        ethMockStrategy.initialize(address(ethVault), address(harvester), _wants, _ratios);

        IVault.StrategyAdd[] memory _strategyAdds = new IVault.StrategyAdd[](2);

        _strategyAdds[0] = IVault.StrategyAdd({
        strategy: address(ethMockStrategy),
        profitLimitRatio: uint256(100),
        lossLimitRatio: uint256(100),
        targetDebt:uint256(1e22)
        });

        _strategyAdds[1] = IVault.StrategyAdd({
        strategy: address(otherEthMock3CoinStrategy),
        profitLimitRatio: uint256(100),
        lossLimitRatio: uint256(100),
        targetDebt:uint256(1e22)

        });

        iETHVault.addStrategies(_strategyAdds);

        uint256 _ethAmount = 10000e18;
        uint256 _stETHAmount = 10000e18;
        uint256 _wETHAmount = 10000e18;
        vm.stopPrank();

        vm.startPrank(USER);
        deal(USER, _ethAmount * 2 + _stETHAmount);
        IEREC20Mint(STETH_ADDRESS).submit{value: _stETHAmount}(USER);
        IERC20(STETH_ADDRESS).transfer(address(ethVault),_stETHAmount);

        payable(address(ethVault)).transfer(_ethAmount);

        deal(WETH_ADDRESS, address(ethVault), _wETHAmount);
        vm.stopPrank();

        vm.startPrank(GOVERNANOR);

        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _balanceOfToken(NativeToken.NATIVE_TOKEN, address(ethVault));
        _amounts[1] = _balanceOfToken(STETH_ADDRESS, address(ethVault));
        _amounts[2] = _balanceOfToken(WETH_ADDRESS, address(ethVault));

        uint256 totalLendAsset = calculateLendValue(
            ethMockStrategy,
            _ratios,
            _amounts,
            _wants,
            _wants,
            valueInterpreter,
            1
        );
        console2.log("====totalLendAsset is ===",totalLendAsset);
        uint256 _minDeltaAssets = totalLendAsset - 2;
        uint256 __minDeltaAssets = iETHVault.lend(address(ethMockStrategy), _wants, _amounts,_minDeltaAssets);
        console2.log("====_minDeltaAssets is ===",__minDeltaAssets);

        vm.stopPrank();

        assertGt(ethMockStrategy.estimatedTotalAssets(),0);

        assertEq(_balanceOfToken(NativeToken.NATIVE_TOKEN, address(ethVault))/10, _amounts[0]/20);
        assertEq(_balanceOfToken(STETH_ADDRESS, address(ethVault))/10, 0);
        assertEq(_balanceOfToken(WETH_ADDRESS, address(ethVault))/10, _amounts[2]/10);
    }

    function testAddAndRemoveStrategies() public {
        address[] memory _strategies = iVault.getStrategies();
        assertEq(_strategies.length, 0);

        IVault.StrategyAdd[] memory _strategyAdds = new IVault.StrategyAdd[](1);
        _strategyAdds[0] = IVault.StrategyAdd({
            strategy: address(mock3CoinStrategy),
            profitLimitRatio: uint256(100),
            lossLimitRatio: uint256(100),
            targetDebt:uint256(1e24)

        });

        vm.startPrank(GOVERNANOR);
        iVault.addStrategies(_strategyAdds);
        _strategies = iVault.getStrategies();
        assertEq(_strategies.length, 1);

        iVault.checkActiveStrategy(address(mock3CoinStrategy));

        address[] memory _removeStrategies = new address[](1);
        _removeStrategies[0] = address(mock3CoinStrategy);
        iVault.removeStrategies(_removeStrategies);
        _strategies = iVault.getStrategies();
        assertEq(_strategies.length, 0);
        _strategyAdds = new IVault.StrategyAdd[](2);
        _strategyAdds[0] = IVault.StrategyAdd({
        strategy: address(mock3CoinStrategy),
        profitLimitRatio: uint256(100),
        lossLimitRatio: uint256(100),
        targetDebt:uint256(1e24)
        });

        _strategyAdds[1] = IVault.StrategyAdd({
        strategy: address(otherMock3CoinStrategy),
        profitLimitRatio: uint256(100),
        lossLimitRatio: uint256(100),
        targetDebt:uint256(1e24)
        });

        iVault.addStrategies(_strategyAdds);
        _strategies = iVault.getStrategies();
        vm.stopPrank();
        assertEq(_strategies.length, _strategyAdds.length);
    }

    function testSetStrategyEnforceChangeLimit() public {
        testAddAndRemoveAssets();
        testAddAndRemoveStrategies();

        address[] memory _strategies = iVault.getStrategies();
        IVault.StrategyParams memory strategyParam = iVault.strategies(_strategies[0]);
        assertEq(strategyParam.enforceChangeLimit,true);

        vm.startPrank(GOVERNANOR);
        iVault.setStrategyEnforceChangeLimit(_strategies[0], false);
        strategyParam = iVault.strategies(_strategies[0]);
        assertEq(strategyParam.enforceChangeLimit,false);
        vm.stopPrank();
    
    }

    function testSetStrategySetLimitRatio() public {
        testAddAndRemoveAssets();
        testAddAndRemoveStrategies();

        address[] memory _strategies = iVault.getStrategies();
        IVault.StrategyParams memory strategyParam = iVault.strategies(_strategies[0]);
        assertEq(strategyParam.lossLimitRatio,100);
        assertEq(strategyParam.profitLimitRatio,100);

        vm.startPrank(GOVERNANOR);
        iVault.setStrategySetLimitRatio(_strategies[0], 200,200);
        strategyParam = iVault.strategies(_strategies[0]);
        assertEq(strategyParam.lossLimitRatio,200);
        assertEq(strategyParam.profitLimitRatio,200);
        vm.stopPrank();
    
    }

    function testAddAndRemoveStrategiesWithETHi() public {
        address[] memory _strategies = iETHVault.getStrategies();
        assertEq(_strategies.length, 0);

        IVault.StrategyAdd[] memory _strategyAdds = new IVault.StrategyAdd[](1);
        _strategyAdds[0] = IVault.StrategyAdd({
            strategy: address(ethMock3CoinStrategy),
            profitLimitRatio: uint256(100),
            lossLimitRatio: uint256(100),
            targetDebt:uint256(1e22)
        });

        vm.startPrank(GOVERNANOR);
        iETHVault.addStrategies(_strategyAdds);
        _strategies = iETHVault.getStrategies();
        assertEq(_strategies.length, 1);

        address[] memory _removeStrategies = new address[](1);
        _removeStrategies[0] = address(ethMock3CoinStrategy);
        iETHVault.removeStrategies(_removeStrategies);
        _strategies = iETHVault.getStrategies();
        assertEq(_strategies.length, 0);


        _strategyAdds = new IVault.StrategyAdd[](2);
        _strategyAdds[0] = IVault.StrategyAdd({
        strategy: address(ethMock3CoinStrategy),
        profitLimitRatio: uint256(100),
        lossLimitRatio: uint256(100),
        targetDebt:uint256(1e22)
        });

        _strategyAdds[1] = IVault.StrategyAdd({
        strategy: address(otherEthMock3CoinStrategy),
        profitLimitRatio: uint256(100),
        lossLimitRatio: uint256(100),
        targetDebt:uint256(1e22)
        });

        iETHVault.addStrategies(_strategyAdds);
        _strategies = iETHVault.getStrategies();
        vm.stopPrank();
        assertEq(_strategies.length, _strategyAdds.length);
    }

    function testSetAndIncreaseStrategyTargetDebts() public {

        testAddAndRemoveAssets();
        testAddAndRemoveStrategies();

        vm.startPrank(GOVERNANOR);
        address[] memory strategies = new address[](2);
        strategies[0] = address(mock3CoinStrategy);
        strategies[1] = address(otherMock3CoinStrategy);
        uint256[] memory newTargetDebts = new uint256[](2);
        newTargetDebts[0] = 2000e18;
        newTargetDebts[1] = 5000e18;
        iVault.setStrategyTargetDebts(strategies,newTargetDebts);
        for(uint256 i=0; i<strategies.length; i++) {
            IVault.StrategyParams memory strategyParam = iVault.strategies(strategies[i]);
            assertEq(strategyParam.targetDebt, newTargetDebts[i]);
        }

        iVault.increaseStrategyTargetDebts(strategies,newTargetDebts);
        for(uint256 i=0; i<strategies.length; i++) {
            IVault.StrategyParams memory strategyParam = iVault.strategies(strategies[i]);
            assertEq(strategyParam.targetDebt, newTargetDebts[i]+newTargetDebts[i]);
        }

        vm.stopPrank();

    }
    function testFailSetAndIncreaseStrategyTargetDebts() public {

        testAddAndRemoveAssets();
        testAddAndRemoveStrategies();

        vm.startPrank(USER);
        address[] memory strategies = new address[](2);
        strategies[0] = address(mock3CoinStrategy);
        strategies[1] = address(otherMock3CoinStrategy);
        uint256[] memory newTargetDebts = new uint256[](2);
        newTargetDebts[0] = 2000e18;
        newTargetDebts[1] = 5000e18;
        iVault.setStrategyTargetDebts(strategies,newTargetDebts);//no keeper call =>Fail

        iVault.increaseStrategyTargetDebts(strategies,newTargetDebts);//no keeper call =>Fail

        vm.stopPrank();

    }

    function testSetExchangeRouter() public {
        address oneInchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;
        address paraRouter = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;
        address paraTransferProxy = 0x216B4B4Ba9F3e719726886d34a177484278Bfcae;
        testAddAndRemoveAssets();
        testAddAndRemoveStrategies();
        assertEq(iVault.oneInchRouter(), oneInchRouter);
        assertEq(iVault.paraRouter(), paraRouter);
        assertEq(iVault.paraTransferProxy(), paraTransferProxy);

        vm.startPrank(GOVERNANOR);
        address newRouter = address(mock3CoinStrategy);
        
        iVault.set1inchRouter(newRouter);
        iVault.setParaRouter(newRouter);
        iVault.setParaTransferProxy(newRouter);

        assertEq(iVault.oneInchRouter(), newRouter);
        assertEq(iVault.paraRouter(), newRouter);
        assertEq(iVault.paraTransferProxy(), newRouter);
        
        vm.stopPrank();
    }

    function testFailSetExchangeRouter() public {
        testAddAndRemoveAssets();
        testAddAndRemoveStrategies();

        //check access control
        vm.startPrank(USER);
        address newRouter = address(mock3CoinStrategy);
        iVault.set1inchRouter(newRouter);
        iVault.setParaRouter(newRouter);
        iVault.setParaTransferProxy(newRouter);
        
        vm.stopPrank();

        //check non zero address
        vm.startPrank(GOVERNANOR);
        address ZERO_ADDRESS = address(0);
        
        iVault.set1inchRouter(ZERO_ADDRESS);
        iVault.setParaRouter(ZERO_ADDRESS);
        iVault.setParaTransferProxy(ZERO_ADDRESS);
        
        vm.stopPrank();
    }

    function testSetAndIncreaseStrategyTargetDebtsWithETHi() public {

        testAddAndRemoveAssetsWithETHi();
        testAddAndRemoveStrategiesWithETHi();

        vm.startPrank(GOVERNANOR);
        address[] memory strategies = new address[](2);
        strategies[0] = address(ethMock3CoinStrategy);
        strategies[1] = address(otherEthMock3CoinStrategy);
        uint256[] memory newTargetDebts = new uint256[](2);
        newTargetDebts[0] = 1e18;
        newTargetDebts[1] = 20e18;
        iETHVault.setStrategyTargetDebts(strategies,newTargetDebts);
        for(uint256 i=0; i<strategies.length; i++) {
            IVault.StrategyParams memory strategyParam = iETHVault.strategies(strategies[i]);
            assertEq(strategyParam.targetDebt, newTargetDebts[i]);
        }

        iETHVault.increaseStrategyTargetDebts(strategies,newTargetDebts);
        for(uint256 i=0; i<strategies.length; i++) {
            IVault.StrategyParams memory strategyParam = iETHVault.strategies(strategies[i]);
            assertEq(strategyParam.targetDebt, newTargetDebts[i]+newTargetDebts[i]);
        }

        vm.stopPrank();

    }

    function testFailSetVaultBufferAddress() public {
        vm.prank(GOVERNANOR);
        iVault.setVaultBufferAddress(address(vaultBuffer));
    }

    function testFailSetVaultBufferAddressWithETHi() public {
        vm.prank(GOVERNANOR);
        iETHVault.setVaultBufferAddress(address(vaultBuffer));
    }

    function testFailSetPegTokenAddress() public {
        vm.prank(GOVERNANOR);
        iVault.setPegTokenAddress(address(pegToken));
    }

    function testFailSetPegTokenAddressWithETHi() public {
        vm.prank(GOVERNANOR);
        iETHVault.setPegTokenAddress(address(pegToken));
    }

    function testEstimateMint() public {
        testAddAndRemoveAssets();
        testAddAndRemoveStrategies();
        address[] memory _assets = new address[](3);
        _assets[0] = USDC_ADDRESS;
        _assets[1] = USDT_ADDRESS;
        _assets[2] = DAI_ADDRESS;
        uint256 _usdcAmount = 10000e6;
        uint256 _usdtAmount = 10000e6;
        uint256 _daiAmount = 10000e18;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _usdcAmount;
        _amounts[1] = _usdtAmount;
        _amounts[2] = _daiAmount;
        uint256 _ticketAmount = iVault.estimateMint(_assets, _amounts);
        uint256 _valueInUSD = valueInterpreter.calcCanonicalAssetValueInUsd(USDC_ADDRESS, _usdcAmount) +
            valueInterpreter.calcCanonicalAssetValueInUsd(USDT_ADDRESS, _usdtAmount) +
            valueInterpreter.calcCanonicalAssetValueInUsd(DAI_ADDRESS, _daiAmount);

        assertEq(_ticketAmount, _valueInUSD);
    }

    function testEstimateMintWithETHi() public {
        testAddAndRemoveAssetsWithETHi();
        testAddAndRemoveStrategiesWithETHi();
        address[] memory _assets = new address[](3);
        _assets[0] = NativeToken.NATIVE_TOKEN;
        _assets[1] = STETH_ADDRESS;
        _assets[2] = WETH_ADDRESS;
        uint256 _ethAmount = 10000e18;
        uint256 _stETHAmount = 10000e18;
        uint256 _wETHAmount = 10000e18;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _ethAmount;
        _amounts[1] = _stETHAmount;
        _amounts[2] = _wETHAmount;
        uint256 _ticketAmount = iETHVault.estimateMint(_assets, _amounts);
        uint256 _valueInETH = valueInterpreter.calcCanonicalAssetValueInEth(
            NativeToken.NATIVE_TOKEN,
            _ethAmount
        ) +
            valueInterpreter.calcCanonicalAssetValueInEth(STETH_ADDRESS, _stETHAmount) +
            valueInterpreter.calcCanonicalAssetValueInEth(WETH_ADDRESS, _wETHAmount);

        assertEq(_ticketAmount, _valueInETH);
    }

    function testDeposit() public {
        testAddAndRemoveAssets();
        testAddAndRemoveStrategies();
        address[] memory _assets = new address[](3);
        _assets[0] = USDC_ADDRESS;
        _assets[1] = USDT_ADDRESS;
        _assets[2] = DAI_ADDRESS;
        uint256 _usdcAmount = 10000e6;
        uint256 _usdtAmount = 10000e6;
        uint256 _daiAmount = 10000e18;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _usdcAmount;
        _amounts[1] = _usdtAmount;
        _amounts[2] = _daiAmount;
        uint256 _minimumAmount = 0;
        deal(USDC_ADDRESS, USER, _usdcAmount);
        deal(USDT_ADDRESS, USER, _usdtAmount);
        deal(DAI_ADDRESS, USER, _daiAmount);

        vm.startPrank(USER);
        _safeApprove(USDC_ADDRESS, address(vault), _usdcAmount);
        _safeApprove(USDT_ADDRESS, address(vault), _usdtAmount);
        _safeApprove(DAI_ADDRESS, address(vault), _daiAmount);
        iVault.mint(_assets, _amounts, _minimumAmount);
        vm.stopPrank();
        uint256 _ticketAmount = vaultBuffer.balanceOf(USER);
        uint256 _valueInUSD = valueInterpreter.calcCanonicalAssetValueInUsd(USDC_ADDRESS, _usdcAmount) +
            valueInterpreter.calcCanonicalAssetValueInUsd(USDT_ADDRESS, _usdtAmount) +
            valueInterpreter.calcCanonicalAssetValueInUsd(DAI_ADDRESS, _daiAmount);

        assertEq(_ticketAmount, _valueInUSD);

        uint256 valueOfTrackedTokens =  iVault.valueOfTrackedTokens();
        assertEq(valueOfTrackedTokens, 0);
        uint256 valueOfTrackedTokensIncludeVaultBuffer =  iVault.valueOfTrackedTokensIncludeVaultBuffer();
        console2.log("valueOfTrackedTokensIncludeVaultBuffer is",valueOfTrackedTokensIncludeVaultBuffer);
        
        uint256 valueOfTrackedTokensInVaultBuffer =  iVault.valueOfTrackedTokensInVaultBuffer();
        console2.log("valueOfTrackedTokensInVaultBuffer is",valueOfTrackedTokensInVaultBuffer);

        assertEq(valueOfTrackedTokensIncludeVaultBuffer, valueOfTrackedTokensInVaultBuffer);

    }

    function testDepositWithETHi() public {
        testAddAndRemoveAssetsWithETHi();
        testAddAndRemoveStrategiesWithETHi();
        address[] memory _assets = new address[](3);
        _assets[0] = NativeToken.NATIVE_TOKEN;
        _assets[1] = STETH_ADDRESS;
        _assets[2] = WETH_ADDRESS;
        uint256 _ethAmount = 10000e18;
        uint256 _stETHAmount = 10000e18;
        uint256 _wETHAmount = 10000e18;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _ethAmount;
        _amounts[1] = _stETHAmount;
        _amounts[2] = _wETHAmount;
        uint256 _minimumAmount = 0;
        vm.startPrank(USER);
        deal(USER, _ethAmount * 2 + _stETHAmount);
        IEREC20Mint(STETH_ADDRESS).submit{value: _stETHAmount}(USER);
        deal(WETH_ADDRESS, USER, _wETHAmount);

        _safeApprove(STETH_ADDRESS, address(ethVault), _stETHAmount);
        _safeApprove(WETH_ADDRESS, address(ethVault), _wETHAmount);
        iETHVault.mint{value: _ethAmount}(_assets, _amounts, _minimumAmount);
        vm.stopPrank();
        uint256 _ticketAmount = ethVaultBuffer.balanceOf(USER);

        uint256 _valueInETH = valueInterpreter.calcCanonicalAssetValueInEth(
            NativeToken.NATIVE_TOKEN,
            _ethAmount
        ) +
            valueInterpreter.calcCanonicalAssetValueInEth(STETH_ADDRESS, _stETHAmount) +
            valueInterpreter.calcCanonicalAssetValueInEth(WETH_ADDRESS, _wETHAmount);

        assertEq(_ticketAmount, _valueInETH);

        uint256 valueOfTrackedTokens =  iETHVault.valueOfTrackedTokens();
        assertEq(valueOfTrackedTokens, 0);
        uint256 valueOfTrackedTokensIncludeVaultBuffer =  iETHVault.valueOfTrackedTokensIncludeVaultBuffer();
        console2.log("valueOfTrackedTokensIncludeVaultBuffer is",valueOfTrackedTokensIncludeVaultBuffer);
        
        uint256 valueOfTrackedTokensInVaultBuffer =  iETHVault.valueOfTrackedTokensInVaultBuffer();
        console2.log("valueOfTrackedTokensInVaultBuffer is",valueOfTrackedTokensInVaultBuffer);

        assertEq(valueOfTrackedTokensIncludeVaultBuffer, valueOfTrackedTokensInVaultBuffer);
    }

    function testWithdrawlQueueOpMethod() public {
        testDeposit();
        vm.startPrank(GOVERNANOR);
        address[] memory _queues = new address[](2);
        _queues[0] = address(mock3CoinStrategy);
        _queues[1] = address(otherMock3CoinStrategy);
        iVault.setWithdrawalQueue(_queues);

        address[] memory wthdrawalQueue = iVault.getWithdrawalQueue();
        assertEq(wthdrawalQueue[0],address(mock3CoinStrategy));
        assertEq(wthdrawalQueue[1],address(otherMock3CoinStrategy));

        address[] memory removeWthdrawalQueue = new address[](1);
        removeWthdrawalQueue[0] = address(mock3CoinStrategy);
        iVault.removeStrategyFromQueue(removeWthdrawalQueue);

        address[] memory wthdrawalQueueAfterRemove = iVault.getWithdrawalQueue();
        assertEq(wthdrawalQueueAfterRemove[0],address(otherMock3CoinStrategy));
        assertEq(wthdrawalQueueAfterRemove[1],address(0));

        iVault.forceRemoveStrategy(address(otherMock3CoinStrategy));
        address[] memory wthdrawalQueueAfterForceRemove = iVault.getWithdrawalQueue();
        //assertEq(wthdrawalQueueAfterForceRemove.length, 0);
        assertEq(wthdrawalQueueAfterForceRemove[0],address(0));
        assertEq(wthdrawalQueueAfterForceRemove[1],address(0));

    }

    function testAdjustPosition() public {
        testDeposit();
        vm.startPrank(GOVERNANOR);
        iVault.setRebaseThreshold(uint256(1));
        uint256 _beforeAdjustPositionOfVault = _balanceOfToken(USDT_ADDRESS, address(vault));
        uint256 _beforeAdjustPositionOfVaultBuffer = _balanceOfToken(USDT_ADDRESS, address(vaultBuffer));
        uint256 pegTokenPrice = iVault.getPegTokenPrice();
        assertEq(pegTokenPrice,1e18);
        address[] memory _strategies = new address[](2);
        _strategies[0] = address(mock3CoinStrategy);
        _strategies[1] = address(otherMock3CoinStrategy);
        vault.reportByKeeper(_strategies);
        mock3CoinStrategy.reportToVault();
        mock3CoinStrategy.reportWithoutClaim();
        iVault.startAdjustPosition();
        pegTokenPrice = iVault.getPegTokenPrice();
        assertEq(pegTokenPrice,1e18);
        uint256 _afterAdjustPositionOfVault = _balanceOfToken(USDT_ADDRESS, address(vault));
        uint256 _afterAdjustPositionOfVaultBuffer = _balanceOfToken(USDT_ADDRESS, address(vaultBuffer));

        assertEq(
            _beforeAdjustPositionOfVault + _beforeAdjustPositionOfVaultBuffer,
            _afterAdjustPositionOfVault + _afterAdjustPositionOfVaultBuffer
        );
        assertGt(_afterAdjustPositionOfVault, _beforeAdjustPositionOfVault);

        address[] memory _queues = new address[](2);
        _queues[0] = address(mock3CoinStrategy);
        _queues[1] = address(otherMock3CoinStrategy);
        iVault.setWithdrawalQueue(_queues);

        address[] memory _tokens = new address[](3);
        _tokens[0] = USDT_ADDRESS;
        _tokens[1] = USDC_ADDRESS;
        _tokens[2] = DAI_ADDRESS;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _balanceOfToken(USDT_ADDRESS, address(vault))/2;
        _amounts[1] = _balanceOfToken(USDC_ADDRESS, address(vault))/2;
        _amounts[2] = _balanceOfToken(DAI_ADDRESS, address(vault))/2;
        uint256 _valueInUSD;
        {
            iVault.lend(address(mock3CoinStrategy), _tokens, _amounts,0);
            uint256[] memory _otherAmounts = new uint256[](3);
            _otherAmounts[0] = _balanceOfToken(USDT_ADDRESS, address(vault));
            _otherAmounts[1] = _balanceOfToken(USDC_ADDRESS, address(vault));
            _otherAmounts[2] = _balanceOfToken(DAI_ADDRESS, address(vault));

            iVault.lend(address(otherMock3CoinStrategy), _tokens, _otherAmounts,0);

            _valueInUSD = valueInterpreter.calcCanonicalAssetValueInUsd(USDC_ADDRESS, _amounts[1]*2) +
            valueInterpreter.calcCanonicalAssetValueInUsd(USDT_ADDRESS, _amounts[0]*2) +
            valueInterpreter.calcCanonicalAssetValueInUsd(DAI_ADDRESS, _amounts[2]*2);
        }

        (address[] memory _wants, uint256[] memory _ratios) = mock3CoinStrategy.getWantsInfo();
        uint256 _wantsLength = _wants.length;

        uint256 _minProductIndex;
        bool _isWantRatioIgnorable = mock3CoinStrategy.isWantRatioIgnorable();
        if (!_isWantRatioIgnorable && _wantsLength > 1) {
            for (uint256 i = 1; i < _wantsLength; i++) {
                if (_ratios[i] == 0) {
                    //0 is free
                    continue;
                } else if (_ratios[_minProductIndex] == 0) {
                    //minProductIndex is assigned to the first index whose proportion is not 0
                    _minProductIndex = i;
                } else if (
                    _amounts[_minProductIndex] * _ratios[i] > _amounts[i] * _ratios[_minProductIndex]
                ) {
                    _minProductIndex = i;
                }
            }
        }

        uint256 _minAmount = _amounts[_minProductIndex];
        uint256 _minAspect = _ratios[_minProductIndex];
        for (uint256 i = 0; i < _wantsLength; i++) {
            uint256 _actualAmount = _amounts[i];
            if (_actualAmount > 0) {
                if (!_isWantRatioIgnorable ) {
                        if (_ratios[i] > 0) {
                            _actualAmount = (_ratios[i] * _minAmount) / _minAspect;
                            assertEq(_balanceOfToken(_wants[i], address(mock3CoinStrategy)), _actualAmount);
                        }else{
                           _actualAmount = 0;
                           assertEq(_balanceOfToken(_wants[i], address(mock3CoinStrategy)), _actualAmount);
                           continue;
                        }
                }
            }
        }

        iVault.endAdjustPosition();
        vaultBuffer.distributeWhenDistributing();

        vm.stopPrank();

        uint256 _usdiAmount = pegToken.balanceOf(USER);
        uint256 getPegTokenPrice = iVault.getPegTokenPrice();
        assertEq(getPegTokenPrice,1e18);

        assertEq(_usdiAmount, _valueInUSD);

        uint256 valueOfTrackedTokensInVault =  iVault.valueOfTrackedTokens();
        uint256 valueOfTrackedTokensIncludeVaultBuffer =  iVault.valueOfTrackedTokensIncludeVaultBuffer();        
        uint256 valueOfTrackedTokensInVaultBuffer =  iVault.valueOfTrackedTokensInVaultBuffer();

        assertEq(valueOfTrackedTokensInVaultBuffer, 0);
        assertEq(valueOfTrackedTokensIncludeVaultBuffer, valueOfTrackedTokensInVault);

        uint256 totalDebt = iVault.totalDebt();
        console2.log("totalDebt",totalDebt);
        uint256 totalAssets = iVault.totalAssets();
        assertEq(valueOfTrackedTokensInVault + totalDebt, totalAssets);

        uint256 totalValueInVaultBuffer = iVault.totalValueInVaultBuffer();
        assertEq(0, totalValueInVaultBuffer);

        uint256 totalAssetsIncludeVaultBuffer = iVault.totalAssetsIncludeVaultBuffer();
        assertEq(valueOfTrackedTokensIncludeVaultBuffer + totalDebt, totalAssetsIncludeVaultBuffer);

    }

    function testAdjustPositionWithETHi() public {
        testDepositWithETHi();
        vm.startPrank(GOVERNANOR);
        iETHVault.setRebaseThreshold(uint256(1));
        uint256 _beforeAdjustPositionOfVault = _balanceOfToken(
            NativeToken.NATIVE_TOKEN,
            address(ethVault)
        );
        uint256 _beforeAdjustPositionOfVaultBuffer = _balanceOfToken(
            NativeToken.NATIVE_TOKEN,
            address(ethVaultBuffer)
        );
        uint256 pegTokenPrice = iETHVault.getPegTokenPrice();
        assertEq(pegTokenPrice,1e18);
        address[] memory _strategies = new address[](2);
        _strategies[0] = address(ethMock3CoinStrategy);
        _strategies[1] = address(otherEthMock3CoinStrategy);
        iETHVault.reportByKeeper(_strategies);
        ethMock3CoinStrategy.reportToVault();
        ethMock3CoinStrategy.reportWithoutClaim();

        iETHVault.startAdjustPosition();
        pegTokenPrice = iETHVault.getPegTokenPrice();
        assertEq(pegTokenPrice,1e18);
        uint256 _afterAdjustPositionOfVault = _balanceOfToken(
            NativeToken.NATIVE_TOKEN,
            address(ethVault)
        );
        uint256 _afterAdjustPositionOfVaultBuffer = _balanceOfToken(
            NativeToken.NATIVE_TOKEN,
            address(ethVaultBuffer)
        );

        assertEq(
            _beforeAdjustPositionOfVault + _beforeAdjustPositionOfVaultBuffer,
            _afterAdjustPositionOfVault + _afterAdjustPositionOfVaultBuffer
        );
        assertGt(_afterAdjustPositionOfVault, _beforeAdjustPositionOfVault);

        address[] memory _queues = new address[](2);
        _queues[0] = address(ethMock3CoinStrategy);
        _queues[1] = address(otherEthMock3CoinStrategy);
        iETHVault.setWithdrawalQueue(_queues);

        address[] memory _tokens = new address[](3);
        _tokens[0] = NativeToken.NATIVE_TOKEN;
        _tokens[1] = STETH_ADDRESS;
        _tokens[2] = WETH_ADDRESS;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _balanceOfToken(NativeToken.NATIVE_TOKEN, address(ethVault))/2;
        _amounts[1] = _balanceOfToken(STETH_ADDRESS, address(ethVault))/2;
        _amounts[2] = _balanceOfToken(WETH_ADDRESS, address(ethVault))/2;
        uint256 _valueInETH;
        {
            iETHVault.lend(address(ethMock3CoinStrategy), _tokens, _amounts,0);

            uint256[] memory _otherAmounts = new uint256[](3);
        _otherAmounts[0] = _balanceOfToken(NativeToken.NATIVE_TOKEN, address(ethVault));
        _otherAmounts[1] = _balanceOfToken(STETH_ADDRESS, address(ethVault));
        _otherAmounts[2] = _balanceOfToken(WETH_ADDRESS, address(ethVault));
            iETHVault.lend(address(otherEthMock3CoinStrategy), _tokens, _otherAmounts,0);

            _valueInETH = valueInterpreter.calcCanonicalAssetValueInEth(STETH_ADDRESS, _amounts[1]*2) +
            valueInterpreter.calcCanonicalAssetValueInEth(NativeToken.NATIVE_TOKEN, _amounts[0]*2) +
            valueInterpreter.calcCanonicalAssetValueInEth(WETH_ADDRESS, _amounts[2]*2);
        }

        (address[] memory _wants, uint256[] memory _ratios) = ethMock3CoinStrategy.getWantsInfo();
        uint256 _wantsLength = _wants.length;

        uint256 _minProductIndex;
        bool _isWantRatioIgnorable = ethMock3CoinStrategy.isWantRatioIgnorable();
        if (!_isWantRatioIgnorable && _wantsLength > 1) {
            for (uint256 i = 1; i < _wantsLength; i++) {
                if (_ratios[i] == 0) {
                    //0 is free
                    continue;
                } else if (_ratios[_minProductIndex] == 0) {
                    //minProductIndex is assigned to the first index whose proportion is not 0
                    _minProductIndex = i;
                } else if (
                    _amounts[_minProductIndex] * _ratios[i] > _amounts[i] * _ratios[_minProductIndex]
                ) {
                    _minProductIndex = i;
                }
            }
        }

        uint256 _minAmount = _amounts[_minProductIndex];
        uint256 _minAspect = _ratios[_minProductIndex];
        for (uint256 i = 0; i < _wantsLength; i++) {
            uint256 _actualAmount = _amounts[i];
            if (_actualAmount > 0) {
                if (!_isWantRatioIgnorable) {
                    if(_ratios[i] > 0) {
                        _actualAmount = (_ratios[i] * _minAmount) / _minAspect;
                        if (_wants[i] == STETH_ADDRESS) {
                            assertEq(
                                (_balanceOfToken(_wants[i], address(ethMock3CoinStrategy)) + 9) / 10,
                                _actualAmount / 10
                            );
                        } else {
                            assertEq(
                                _balanceOfToken(_wants[i], address(ethMock3CoinStrategy)),
                                _actualAmount
                            );
                        }
                    } else {
                        assertEq(
                                _balanceOfToken(_wants[i], address(ethMock3CoinStrategy)),
                                0
                        );
                    }
                    
                }
            }
        }

        iETHVault.endAdjustPosition();
        ethVaultBuffer.distributeWhenDistributing();

        vm.stopPrank();

        uint256 _ethiAmount = ethPegToken.balanceOf(USER);
        uint256 getPegTokenPrice = iETHVault.getPegTokenPrice();
        assertEq(getPegTokenPrice,1e18);

        assertEq(_ethiAmount / 100, _valueInETH / 100);

        uint256 valueOfTrackedTokensInVault =  iETHVault.valueOfTrackedTokens();
        uint256 valueOfTrackedTokensIncludeVaultBuffer =  iETHVault.valueOfTrackedTokensIncludeVaultBuffer();        
        uint256 valueOfTrackedTokensInVaultBuffer =  iETHVault.valueOfTrackedTokensInVaultBuffer();
        
        assertEq(valueOfTrackedTokensInVaultBuffer, 0);
        assertEq(valueOfTrackedTokensIncludeVaultBuffer, valueOfTrackedTokensInVault);

        uint256 totalDebt = iETHVault.totalDebt();
        console2.log("totalDebt",totalDebt);
        uint256 totalAssets = iETHVault.totalAssets();
        assertEq(valueOfTrackedTokensInVault + totalDebt, totalAssets);

        uint256 totalValueInVaultBuffer = iETHVault.totalValueInVaultBuffer();
        assertEq(0, totalValueInVaultBuffer);

        uint256 totalAssetsIncludeVaultBuffer = iETHVault.totalAssetsIncludeVaultBuffer();
        assertEq(valueOfTrackedTokensIncludeVaultBuffer + totalDebt, totalAssetsIncludeVaultBuffer);
    }

    function testWithdraw() public {
        testAdjustPosition();
        uint256 _amount = pegToken.balanceOf(USER) / 4;

        vm.prank(GOVERNANOR);
        iVault.setRedeemFeeBps(1);
        uint256 _redeemFeeBps = iVault.redeemFeeBps();
        uint256 _trusteeFeeBps = iVault.trusteeFeeBps();
        uint256 _minimumAmount = 10;
        vm.prank(USER);
        iVault.burn(_amount, _minimumAmount, _redeemFeeBps, _trusteeFeeBps);
        vm.prank(GOVERNANOR);
        iVault.setRedeemFeeBps(0);
        deal(DAI_ADDRESS,address(iVault),_balanceOfToken(DAI_ADDRESS, address(iVault))+1000);
        vm.prank(GOVERNANOR);
        iVault.setTrusteeFeeBps(1);
        _trusteeFeeBps = iVault.trusteeFeeBps();
        iVault.rebase(_trusteeFeeBps);
        vm.prank(GOVERNANOR);
        iVault.setTrusteeFeeBps(0);
        _trusteeFeeBps = iVault.trusteeFeeBps();

        uint256 _valueInUSD = valueInterpreter.calcCanonicalAssetValueInUsd(
            USDC_ADDRESS,
            _balanceOfToken(USDC_ADDRESS, USER)
        ) +
            valueInterpreter.calcCanonicalAssetValueInUsd(
                USDT_ADDRESS,
                _balanceOfToken(USDT_ADDRESS, USER)
            ) +
            valueInterpreter.calcCanonicalAssetValueInUsd(
                DAI_ADDRESS,
                _balanceOfToken(DAI_ADDRESS, USER)
            );

        assertEq(_amount / 1e19, _valueInUSD / 1e19);
    }

    function testWithdrawWithETHi() public {
        testAdjustPositionWithETHi();
        uint256 _amount = ethPegToken.balanceOf(USER) / 4;
        vm.prank(GOVERNANOR);
        iETHVault.setRedeemFeeBps(1);
        uint256 _redeemFeeBps = iETHVault.redeemFeeBps();
        uint256 _trusteeFeeBps = iETHVault.trusteeFeeBps();
        uint256 _minimumAmount = 0;
        vm.prank(USER);
        (address[] memory _receiveAssets, uint256[] memory _receiveAmounts, uint256 _actuallyReceivedAmount) = iETHVault.burn(
            _amount,
            _minimumAmount,
            _redeemFeeBps,
            _trusteeFeeBps
        );
        vm.prank(GOVERNANOR);
        iETHVault.setRedeemFeeBps(0);
        deal(address(iETHVault),_balanceOfToken(NATIVE_TOKEN_ADDRESS, address(iETHVault))+1000);
        vm.prank(GOVERNANOR);
        iETHVault.setTrusteeFeeBps(1);
        _trusteeFeeBps = iETHVault.trusteeFeeBps();

        iETHVault.rebase(_trusteeFeeBps);
        vm.prank(GOVERNANOR);
        iETHVault.setTrusteeFeeBps(0);
        _trusteeFeeBps = iETHVault.trusteeFeeBps();
        uint256 _valueInETH;
        for (uint256 i = 0; i < _receiveAssets.length; i++) {
            _valueInETH =
                _valueInETH +
                valueInterpreter.calcCanonicalAssetValueInEth(_receiveAssets[i], _receiveAmounts[i]);
        }

        assertEq(_amount / 1e19, _valueInETH / 1e19);
    }

    function testSecondDeposit() public {
        testWithdraw();

        address[] memory _assets = new address[](3);
        _assets[0] = USDC_ADDRESS;
        _assets[1] = USDT_ADDRESS;
        _assets[2] = DAI_ADDRESS;
        uint256 _usdcAmount = 10000e6;
        uint256 _usdtAmount = 10000e6;
        uint256 _daiAmount = 10000e18;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _usdcAmount;
        _amounts[1] = _usdtAmount;
        _amounts[2] = _daiAmount;
        uint256 _minimumAmount = 100;
        deal(USDC_ADDRESS, FRIEND, _usdcAmount);
        deal(USDT_ADDRESS, FRIEND, _usdtAmount);
        deal(DAI_ADDRESS, FRIEND, _daiAmount);

        vm.startPrank(FRIEND);
        _safeApprove(USDC_ADDRESS, address(vault), _usdcAmount);
        _safeApprove(USDT_ADDRESS, address(vault), _usdtAmount);
        _safeApprove(DAI_ADDRESS, address(vault), _daiAmount);
        iVault.mint(_assets, _amounts, _minimumAmount);
        vm.stopPrank();

        vm.startPrank(GOVERNANOR);
        iVault.startAdjustPosition();
        uint256 _totalDebtOfBeforeRedeem = iVault.totalDebt();
        uint256 _totalAssetsOfBeforeRedeem = iVault.totalAssets();
        iVault.redeem(address(mock3CoinStrategy), _totalDebtOfBeforeRedeem / 5, 0);
        uint256 _totalDebtOfAfterRedeem = iVault.totalDebt();
        uint256 _totalAssetsOfAfterRedeem = iVault.totalAssets();

        assertEq(_totalAssetsOfBeforeRedeem, _totalAssetsOfAfterRedeem);
        assertGt(_totalDebtOfBeforeRedeem, _totalDebtOfAfterRedeem);

        mock3CoinStrategy.transferToken(
            FRIEND,
            USDC_ADDRESS,
            _balanceOfToken(USDC_ADDRESS, address(vault)) / 100000
        );
        address[] memory _tokens = new address[](3);
        _tokens[0] = USDT_ADDRESS;
        _tokens[1] = USDC_ADDRESS;
        _tokens[2] = DAI_ADDRESS;
        uint256[] memory _lendAmounts = new uint256[](3);
        _lendAmounts[0] = _balanceOfToken(USDT_ADDRESS, address(vault));
        _lendAmounts[1] = _balanceOfToken(USDC_ADDRESS, address(vault));
        _lendAmounts[2] = _balanceOfToken(DAI_ADDRESS, address(vault));

        iVault.lend(address(mock3CoinStrategy), _tokens, _lendAmounts,0);

        iVault.endAdjustPosition();
        vaultBuffer.distributeWhenDistributing();
        vm.stopPrank();

        uint256 _usdiAmount = pegToken.balanceOf(FRIEND);
        uint256 _valueInUSD = valueInterpreter.calcCanonicalAssetValueInUsd(
            USDC_ADDRESS,
            _amounts[1] - _balanceOfToken(USDC_ADDRESS, FRIEND)
        ) +
            valueInterpreter.calcCanonicalAssetValueInUsd(USDT_ADDRESS, _amounts[0]) +
            valueInterpreter.calcCanonicalAssetValueInUsd(DAI_ADDRESS, _amounts[2]);

        assertEq(_usdiAmount / 1e17, _valueInUSD / 1e17);

        uint256 totalValueInVault =  iVault.valueOfTrackedTokens();
        uint256 totalValueInStrategies =  iVault.totalValueInStrategies();
        uint256 totalValue =  iVault.totalValue();
        assertEq(totalValue, totalValueInVault + totalValueInStrategies);
    }

    function testSecondDepositWithETHi() public {
        testWithdrawWithETHi();

        address[] memory _assets = new address[](3);
        _assets[0] = NativeToken.NATIVE_TOKEN;
        _assets[1] = STETH_ADDRESS;
        _assets[2] = WETH_ADDRESS;
        uint256 _ethAmount = 10000e18;
        uint256 _stETHAmount = 10000e18;
        uint256 _wETHAmount = 10000e18;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _ethAmount;
        _amounts[1] = _stETHAmount;
        _amounts[2] = _wETHAmount;
        uint256 _minimumAmount = 100;
        vm.startPrank(FRIEND);
        deal(FRIEND, _ethAmount * 2 + _stETHAmount);
        IEREC20Mint(STETH_ADDRESS).submit{value: _stETHAmount}(FRIEND);
        deal(WETH_ADDRESS, FRIEND, _wETHAmount);

        _safeApprove(STETH_ADDRESS, address(ethVault), _stETHAmount);
        _safeApprove(WETH_ADDRESS, address(ethVault), _wETHAmount);
        iETHVault.mint{value: _ethAmount}(_assets, _amounts, _minimumAmount);
        vm.stopPrank();

        vm.startPrank(GOVERNANOR);
        iETHVault.startAdjustPosition();
        uint256 _totalDebtOfBeforeRedeem = iETHVault.totalDebt();
        uint256 _totalAssetsOfBeforeRedeem = iETHVault.totalAssets();
        iETHVault.redeem(address(ethMock3CoinStrategy), _totalDebtOfBeforeRedeem / 5, 0);
        uint256 _totalDebtOfAfterRedeem = iETHVault.totalDebt();
        uint256 _totalAssetsOfAfterRedeem = iETHVault.totalAssets();

        assertEq(_totalAssetsOfBeforeRedeem / 10, _totalAssetsOfAfterRedeem / 10);
        assertGt(_totalDebtOfBeforeRedeem, _totalDebtOfAfterRedeem);

        ethMock3CoinStrategy.transferToken(
            FRIEND,
            WETH_ADDRESS,
            _balanceOfToken(WETH_ADDRESS, address(ethVault)) / 100000
        );
        address[] memory _tokens = new address[](3);
        _tokens[0] = NativeToken.NATIVE_TOKEN;
        _tokens[1] = STETH_ADDRESS;
        _tokens[2] = WETH_ADDRESS;
        uint256[] memory _lendAmounts = new uint256[](3);
        _lendAmounts[0] = _balanceOfToken(NativeToken.NATIVE_TOKEN, address(ethVault));
        _lendAmounts[1] = _balanceOfToken(STETH_ADDRESS, address(ethVault));
        _lendAmounts[2] = _balanceOfToken(WETH_ADDRESS, address(ethVault));

        iETHVault.lend(address(ethMock3CoinStrategy), _tokens, _lendAmounts,0);

        iETHVault.endAdjustPosition();
        ethVaultBuffer.distributeWhenDistributing();
        vm.stopPrank();

        uint256 _ethiAmount = ethPegToken.balanceOf(FRIEND);
        uint256 _valueInETH = valueInterpreter.calcCanonicalAssetValueInEth(STETH_ADDRESS, _amounts[1]) +
            valueInterpreter.calcCanonicalAssetValueInEth(NativeToken.NATIVE_TOKEN, _amounts[0]) +
            valueInterpreter.calcCanonicalAssetValueInEth(
                WETH_ADDRESS,
                _amounts[2] - _balanceOfToken(WETH_ADDRESS, FRIEND)
            );
        console.log("_ethiAmount is ",_ethiAmount);
        assertGe(_ethiAmount / 1e17, _valueInETH / 1e17 + 1 );

        uint256 totalValueInVault =  iETHVault.valueOfTrackedTokens();
        uint256 totalValueInStrategies =  iETHVault.totalValueInStrategies();
        uint256 totalValue =  iETHVault.totalValue();
        assertEq(totalValue, totalValueInVault + totalValueInStrategies);


    }

    function testReport() public {
        testAddAndRemoveStrategies();

        address[] memory _tokens = new address[](3);
        _tokens[0] = USDT_ADDRESS;
        _tokens[1] = USDC_ADDRESS;
        _tokens[2] = DAI_ADDRESS;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = 100000e6;
        _amounts[1] = 200000e6;
        _amounts[2] = 400000e18;
        deal(_tokens[0], address(vault), _amounts[0]);
        deal(_tokens[1], address(vault), _amounts[1]);
        deal(_tokens[2], address(vault), _amounts[2]);
        vm.prank(GOVERNANOR);
        iVault.lend(address(mock3CoinStrategy), _tokens, _amounts,0);

        IVault.StrategyParams memory _strategyParams = iVault.strategies(address(mock3CoinStrategy));
        uint256 _totalDebtOfBeforeReport = _strategyParams.totalDebt;
        uint256 _estimatedTotalAssetsOfBeforeReport = mock3CoinStrategy.estimatedTotalAssets();
        uint256 _usdcAmount = 1000e6;
        uint256 _usdtAmount = 1000e6;
        uint256 _daiAmount = 1000e18;

        deal(
            USDC_ADDRESS,
            address(mock3CoinStrategy),
            _balanceOfToken(USDC_ADDRESS, address(mock3CoinStrategy)) + _usdcAmount
        );
        deal(
            USDT_ADDRESS,
            address(mock3CoinStrategy),
            _balanceOfToken(USDT_ADDRESS, address(mock3CoinStrategy)) + _usdtAmount
        );
        deal(
            DAI_ADDRESS,
            address(mock3CoinStrategy),
            _balanceOfToken(DAI_ADDRESS, address(mock3CoinStrategy)) + _daiAmount
        );

        vm.prank(GOVERNANOR);
        mock3CoinStrategy.reportWithoutClaim();
        _strategyParams = iVault.strategies(address(mock3CoinStrategy));
        uint256 _totalDebtOfAfterReport = _strategyParams.totalDebt;
        uint256 _estimatedTotalAssetsOfAfterReport = mock3CoinStrategy.estimatedTotalAssets();

        uint256 _valueInUSD = valueInterpreter.calcCanonicalAssetValueInUsd(USDC_ADDRESS, _usdcAmount) +
            valueInterpreter.calcCanonicalAssetValueInUsd(USDT_ADDRESS, _usdtAmount) +
            valueInterpreter.calcCanonicalAssetValueInUsd(DAI_ADDRESS, _daiAmount);

        assertEq(_totalDebtOfAfterReport, _totalDebtOfBeforeReport + _valueInUSD);
        assertEq(_estimatedTotalAssetsOfAfterReport, _estimatedTotalAssetsOfBeforeReport + _valueInUSD);

        _totalDebtOfBeforeReport = _strategyParams.totalDebt;
        _estimatedTotalAssetsOfBeforeReport = mock3CoinStrategy.estimatedTotalAssets();

        deal(
            USDC_ADDRESS,
            address(mock3CoinStrategy),
            _balanceOfToken(USDC_ADDRESS, address(mock3CoinStrategy)) + _usdcAmount
        );
        deal(
            USDT_ADDRESS,
            address(mock3CoinStrategy),
            _balanceOfToken(USDT_ADDRESS, address(mock3CoinStrategy)) + _usdtAmount
        );
        deal(
            DAI_ADDRESS,
            address(mock3CoinStrategy),
            _balanceOfToken(DAI_ADDRESS, address(mock3CoinStrategy)) + _daiAmount
        );

        vm.prank(KEEPER);
        address[] memory _strategies = new address[](1);
        _strategies[0] = address(mock3CoinStrategy);
        iVault.reportByKeeper(_strategies);
        vm.stopPrank();
        _strategyParams = iVault.strategies(address(mock3CoinStrategy));

        _totalDebtOfAfterReport = _strategyParams.totalDebt;
        _estimatedTotalAssetsOfAfterReport = mock3CoinStrategy.estimatedTotalAssets();

        assertEq(_totalDebtOfAfterReport, _totalDebtOfBeforeReport + _valueInUSD);
        assertEq(_estimatedTotalAssetsOfAfterReport, _estimatedTotalAssetsOfBeforeReport + _valueInUSD);
    }

    function testReportWithETHi() public {
        testAddAndRemoveStrategiesWithETHi();

        address[] memory _tokens = new address[](3);
        _tokens[0] = NativeToken.NATIVE_TOKEN;
        _tokens[1] = STETH_ADDRESS;
        _tokens[2] = WETH_ADDRESS;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = 1000e18;
        _amounts[1] = 2000e18;
        _amounts[2] = 4000e18;
        deal(address(ethVault), _amounts[0]);
        deal(GOVERNANOR, _amounts[1] * 2);
        address masterMinter = 0x2e59A20f205bB85a89C53f1936454680651E618e;
        deal(masterMinter, 100e18);
        vm.prank(masterMinter);
        IEREC20Mint(STETH_ADDRESS).removeStakingLimit();

        vm.startPrank(GOVERNANOR);
        IEREC20Mint(STETH_ADDRESS).submit{value: _amounts[1] + 10}(GOVERNANOR);

        IEREC20Mint(STETH_ADDRESS).transfer(address(ethVault), _amounts[1] + 2);
        deal(_tokens[2], address(ethVault), _amounts[2]);

        iETHVault.lend(address(ethMock3CoinStrategy), _tokens, _amounts,0);

        IVault.StrategyParams memory _strategyParams = iETHVault.strategies(
            address(ethMock3CoinStrategy)
        );
        uint256 _totalDebtOfBeforeReport = _strategyParams.totalDebt;
        uint256 _estimatedTotalAssetsOfBeforeReport = ethMock3CoinStrategy.estimatedTotalAssets();
        uint256 _ethAmount = 10e18;
        uint256 _stETHAmount = 10e18;
        uint256 _wETHAmount = 10e18;
        deal(
            address(ethMock3CoinStrategy),
            _balanceOfToken(NativeToken.NATIVE_TOKEN, address(ethMock3CoinStrategy)) + _ethAmount
        );

        IEREC20Mint(STETH_ADDRESS).submit{value: _stETHAmount * 2 + 20}(GOVERNANOR);
        IEREC20Mint(STETH_ADDRESS).transfer(address(ethMock3CoinStrategy), _stETHAmount + 2);
        deal(
            WETH_ADDRESS,
            address(ethMock3CoinStrategy),
            _balanceOfToken(WETH_ADDRESS, address(ethMock3CoinStrategy)) + _wETHAmount
        );

        ethMock3CoinStrategy.reportWithoutClaim();
        _strategyParams = iETHVault.strategies(address(ethMock3CoinStrategy));
        uint256 _totalDebtOfAfterReport = _strategyParams.totalDebt;
        uint256 _estimatedTotalAssetsOfAfterReport = ethMock3CoinStrategy.estimatedTotalAssets();

        uint256 _valueInETH = valueInterpreter.calcCanonicalAssetValueInEth(
            NativeToken.NATIVE_TOKEN,
            _ethAmount
        ) +
            valueInterpreter.calcCanonicalAssetValueInEth(STETH_ADDRESS, _stETHAmount) +
            valueInterpreter.calcCanonicalAssetValueInEth(WETH_ADDRESS, _wETHAmount);

        assertEq(_totalDebtOfAfterReport / 10000, (_totalDebtOfBeforeReport + _valueInETH) / 10000  + 1);
        assertEq(_totalDebtOfAfterReport / 10000, (_totalDebtOfBeforeReport + _valueInETH) / 10000  + 1);
        assertEq(
            _estimatedTotalAssetsOfAfterReport / 10000,
            (_estimatedTotalAssetsOfBeforeReport + _valueInETH) / 10000  + 1
        );

        _totalDebtOfBeforeReport = _strategyParams.totalDebt;
        _estimatedTotalAssetsOfBeforeReport = ethMock3CoinStrategy.estimatedTotalAssets();

        deal(
            address(ethMock3CoinStrategy),
            _balanceOfToken(NativeToken.NATIVE_TOKEN, address(ethMock3CoinStrategy)) + _ethAmount
        );
        IEREC20Mint(STETH_ADDRESS).transfer(address(ethMock3CoinStrategy), _stETHAmount + 2);
        deal(
            WETH_ADDRESS,
            address(ethMock3CoinStrategy),
            _balanceOfToken(WETH_ADDRESS, address(ethMock3CoinStrategy)) + _wETHAmount
        );
        vm.stopPrank();

        vm.prank(KEEPER);
        address[] memory _strategies = new address[](1);
        _strategies[0] = address(ethMock3CoinStrategy);
        iETHVault.reportByKeeper(_strategies);
        vm.stopPrank();
        _strategyParams = iETHVault.strategies(address(ethMock3CoinStrategy));

        _totalDebtOfAfterReport = _strategyParams.totalDebt;
        _estimatedTotalAssetsOfAfterReport = ethMock3CoinStrategy.estimatedTotalAssets();

        assertEq(_totalDebtOfAfterReport / 10000, (_totalDebtOfBeforeReport + _valueInETH) / 10000);
        assertEq(_estimatedTotalAssetsOfAfterReport, _estimatedTotalAssetsOfBeforeReport + _valueInETH + 1);
        assertEq(_estimatedTotalAssetsOfAfterReport, _estimatedTotalAssetsOfBeforeReport + _valueInETH + 1);
    }

    function testBurnFromStrategy() public {
        testSecondDeposit();
        uint256 _redeemFeeBps = iVault.redeemFeeBps();
        uint256 _trusteeFeeBps = iVault.trusteeFeeBps();
        uint256 _amount = pegToken.balanceOf(USER);

        mock3CoinStrategy.setPoolWithdrawQuota(mock3CoinStrategy.estimatedTotalAssets()/6);

        vm.prank(USER);
        iVault.burn(_amount, 0, _redeemFeeBps, _trusteeFeeBps);

        assertEq(iVault.valueOfTrackedTokens(), 0);

        mock3CoinStrategy.setPoolWithdrawQuota(mock3CoinStrategy.estimatedTotalAssets());

        _amount = pegToken.balanceOf(FRIEND);
        vm.prank(FRIEND);
        iVault.burn(_amount, 0, _redeemFeeBps, _trusteeFeeBps);

        assertEq(iVault.totalValueInStrategies(), 0);
    }

    function testBurnFromVaultBuffer() public {
        testWithdraw();

        address[] memory _assets = new address[](3);
        _assets[0] = USDC_ADDRESS;
        _assets[1] = USDT_ADDRESS;
        _assets[2] = DAI_ADDRESS;
        uint256 _usdcAmount = 10000e6;
        uint256 _usdtAmount = 10000e6;
        uint256 _daiAmount = 10000e18;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _usdcAmount;
        _amounts[1] = _usdtAmount;
        _amounts[2] = _daiAmount;
        uint256 _minimumAmount = 100;
        deal(USDC_ADDRESS, FRIEND, _usdcAmount);
        deal(USDT_ADDRESS, FRIEND, _usdtAmount);
        deal(DAI_ADDRESS, FRIEND, _daiAmount);

        vm.startPrank(FRIEND);
        _safeApprove(USDC_ADDRESS, address(vault), _usdcAmount);
        _safeApprove(USDT_ADDRESS, address(vault), _usdtAmount);
        _safeApprove(DAI_ADDRESS, address(vault), _daiAmount);
        iVault.mint(_assets, _amounts, _minimumAmount);
        vm.stopPrank();
        uint256 _redeemFeeBps = iVault.redeemFeeBps();
        uint256 _trusteeFeeBps = iVault.trusteeFeeBps();
        uint256 _amount = pegToken.balanceOf(USER);
        vm.prank(USER);
        iVault.burn(_amount, 0, _redeemFeeBps, _trusteeFeeBps);

        assertEq(iVault.valueOfTrackedTokens(), 0);
    }

    function testBurnFromVaultBufferWithETHi() public {
        testWithdrawWithETHi();

        address[] memory _assets = new address[](3);
        _assets[0] = NativeToken.NATIVE_TOKEN;
        _assets[1] = STETH_ADDRESS;
        _assets[2] = WETH_ADDRESS;
        uint256 _ethAmount = 10000e18;
        uint256 _stETHAmount = 10000e18;
        uint256 _wETHAmount = 10000e18;
        uint256[] memory _amounts = new uint256[](3);
        _amounts[0] = _ethAmount;
        _amounts[1] = _stETHAmount;
        _amounts[2] = _wETHAmount;
        uint256 _minimumAmount = 100;
        vm.startPrank(FRIEND);
        deal(FRIEND, _ethAmount * 2 + _stETHAmount);
        IEREC20Mint(STETH_ADDRESS).submit{value: _stETHAmount}(FRIEND);
        deal(WETH_ADDRESS, FRIEND, _wETHAmount);

        _safeApprove(STETH_ADDRESS, address(ethVault), _stETHAmount);
        _safeApprove(WETH_ADDRESS, address(ethVault), _wETHAmount);
        iETHVault.mint{value: _ethAmount}(_assets, _amounts, _minimumAmount);
        vm.stopPrank();

        uint256 _redeemFeeBps = iETHVault.redeemFeeBps();
        uint256 _trusteeFeeBps = iETHVault.trusteeFeeBps();
        uint256 _amount = ethPegToken.balanceOf(USER);
        ethMock3CoinStrategy.setPoolWithdrawQuota(ethMock3CoinStrategy.estimatedTotalAssets()/6);
        vm.prank(USER);
        iETHVault.burn(_amount, 0, _redeemFeeBps, _trusteeFeeBps);

        uint256 valueOfTrackedTokens =  iETHVault.valueOfTrackedTokens();
        console2.log("valueOfTrackedTokens is",valueOfTrackedTokens);
        assertEq(iETHVault.valueOfTrackedTokens(), 0);
    }

    function testBurnFromStrategyWithETHi() public {
        testSecondDepositWithETHi();

        uint256 valueOfTrackedTokens01 =  iETHVault.valueOfTrackedTokens();
        console2.log("valueOfTrackedTokens01 is",valueOfTrackedTokens01);

        uint256 _redeemFeeBps = iETHVault.redeemFeeBps();
        uint256 _trusteeFeeBps = iETHVault.trusteeFeeBps();
        uint256 _amount = ethPegToken.balanceOf(USER);
        ethMock3CoinStrategy.setPoolWithdrawQuota(ethMock3CoinStrategy.estimatedTotalAssets()/6);
        vm.prank(USER);
        iETHVault.burn(_amount, 0, _redeemFeeBps, _trusteeFeeBps);

        uint256 valueOfTrackedTokens =  iETHVault.valueOfTrackedTokens();
        console2.log("valueOfTrackedTokens is",valueOfTrackedTokens);
        assertEq(iETHVault.valueOfTrackedTokens(), 0);

        ethMock3CoinStrategy.setPoolWithdrawQuota(ethMock3CoinStrategy.estimatedTotalAssets());

        _amount = ethPegToken.balanceOf(FRIEND);
        vm.prank(FRIEND);
        iETHVault.burn(_amount, 0, _redeemFeeBps, _trusteeFeeBps);
        assertEq(iETHVault.totalValueInStrategies(), 0);
    }

    function testExchange() public {

        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        
        deal(WETH,address(iETHVault),1 ether);

        console.log("iETHVault address: " ,address(iETHVault));
        address _fromToken = WETH;
        address _toToken = DAI;
        uint256 _fromAmount = 1 ether;
        uint256 _platform1inch = 0;// 1inch
        uint256 _platformPara = 1;//paraswap
        bytes memory  _calldata0 = txData1;
        bytes memory  _calldata1 = txData2;
        
        vm.prank(KEEPER);

        uint256 _returnAmount = iETHVault.exchange(_fromToken, _toToken, _fromAmount, _calldata0, _platform1inch);
        console.log("_returnAmount-1inch",_returnAmount);
        console.log("DAI balance: " ,IERC20(DAI).balanceOf(address(iETHVault)));
        
        deal(WETH,address(iETHVault),1 ether);

        address ICE = 0xf16e81dce15B08F326220742020379B855B87DF9;
        _toToken = ICE;
        deal(WETH,KEEPER,1 ether);
        vm.prank(KEEPER);
        _returnAmount = iETHVault.exchange(_fromToken, _toToken, _fromAmount, _calldata1, _platformPara);
        console.log("_returnAmount-para",_returnAmount);
        console.log("ICE balance: " ,IERC20(ICE).balanceOf(address(iETHVault)));

    }

    function _safeApprove(address _trackedAsset, address _targetAddress, uint256 _amount) internal {
        if (_trackedAsset != NativeToken.NATIVE_TOKEN) {
            IERC20Upgradeable(_trackedAsset).safeApprove(_targetAddress, 0);
            IERC20Upgradeable(_trackedAsset).safeApprove(_targetAddress, _amount);
        }
    }

    function _balanceOfToken(address _trackedAsset, address _owner) internal view returns (uint256) {
        uint256 _balance;
        if (_trackedAsset == NativeToken.NATIVE_TOKEN) {
            _balance = _owner.balance;
        } else {
            _balance = IERC20Upgradeable(_trackedAsset).balanceOf(_owner);
        }
        return _balance;
    }

}
