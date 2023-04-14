// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "brain-forge-std/Test.sol";

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
import "../../exchanges/ExchangeAggregator.sol";
import "../../exchanges/adapters/TestAdapter.sol";
import "../../token/PegToken.sol";
import "../../mock/Mock3CoinStrategy.sol";
import "../../harvester/Harvester.sol";
import "../../library/NativeToken.sol";
import "../../mock/IEREC20Mint.sol";

import "../Constants.sol";

contract ExchangeAggregatorTest is Test {
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

    // const ETH = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
    // const stETH = '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84';
    // const rETH = '0xae78736Cd615f374D3085123A210448E74Fc6393';
    // const cbETH = '0xBe9895146f7AF43049ca1c1AE358B0541Ea49704';
    // const sETH = '0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb';

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
    TestAdapter testAdapter;
    ExchangeAggregator exchangeAggregator;
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

    receive() external payable {}

    function setUp() public {
        console2.log("========ExchangeAggregatorTest========");

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

        testAdapter = new TestAdapter(address(valueInterpreter));
        vm.label(address(testAdapter), "testAdapter");
        address[] memory _exchangeAdapters = new address[](1);
        _exchangeAdapters[0] = address(testAdapter);

        exchangeAggregator = new ExchangeAggregator(_exchangeAdapters, address(accessControlProxy));
        vm.label(address(exchangeAggregator), "exchangeAggregator");
        vm.stopPrank();
    }

    function testRemoveExchangeAdapters() public {
        (address[] memory _exchangeAdapters, string[] memory _identifiers) = exchangeAggregator
            .getExchangeAdapters();
        assertEq(_identifiers.length, 1);

        vm.startPrank(GOVERNANOR);

        exchangeAggregator.removeExchangeAdapters(_exchangeAdapters);
        (address[] memory _newExchangeAdapters, string[] memory _newIdentifiers) = exchangeAggregator
            .getExchangeAdapters();
        assertEq(_newExchangeAdapters.length, 0);
        exchangeAggregator.addExchangeAdapters(_exchangeAdapters);
        (address[] memory _lastExchangeAdapters, string[] memory _lastIdentifiers) = exchangeAggregator
            .getExchangeAdapters();
        assertEq(_lastExchangeAdapters.length, 1);

        vm.stopPrank();
    }

    function testSwapUSDT2USDC() public {
        uint256 _amount = 10e6;
        address _srcToken = USDT_ADDRESS;
        address _dstToken = USDC_ADDRESS;

        address _platform = address(testAdapter);
        uint8 _method = 0;
        bytes memory _data = new bytes(0);
        IExchangeAdapter.SwapDescription memory _swapDesc = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _srcToken,
            dstToken: _dstToken,
            receiver: KEEPER
        });

        deal(_dstToken, _platform, _amount * 2);
        deal(_srcToken, KEEPER, _amount);

        vm.startPrank(KEEPER);
        uint256 _beforeDstTokenBalance = _balanceOfToken(_dstToken, KEEPER);
        console2.log("before swap", _balanceOfToken(_dstToken, KEEPER));
        IERC20Upgradeable(_srcToken).safeApprove(address(exchangeAggregator), 0);
        IERC20Upgradeable(_srcToken).safeApprove(address(exchangeAggregator), _amount);
        exchangeAggregator.swap(_platform, _method, _data, _swapDesc);
        console2.log("after swap", _balanceOfToken(_dstToken, KEEPER));
        vm.stopPrank();
        assertGt(_balanceOfToken(_dstToken, KEEPER), _beforeDstTokenBalance);
    }

    function testBatchSwapUSDTUSDC2DAI() public {
        uint256 _amount = 10e6;
        address _srcToken1 = USDT_ADDRESS;
        address _srcToken2 = USDC_ADDRESS;
        address _dstToken = USDC_ADDRESS;

        address _platform = address(testAdapter);
        uint8 _method = 0;
        bytes memory _data = new bytes(0);
        IExchangeAdapter.SwapDescription memory _swapDesc1 = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _srcToken1,
            dstToken: _dstToken,
            receiver: KEEPER
        });
        IExchangeAdapter.SwapDescription memory _swapDesc2 = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _srcToken2,
            dstToken: _dstToken,
            receiver: KEEPER
        });

        deal(_dstToken, _platform, _amount * 3);
        deal(_srcToken1, KEEPER, _amount);
        deal(_srcToken2, KEEPER, _amount);

        vm.startPrank(KEEPER);
        uint256 _beforeDstTokenBalance = _balanceOfToken(_dstToken, KEEPER);
        console2.log("before swap", _balanceOfToken(_dstToken, KEEPER));
        IERC20Upgradeable(_srcToken1).safeApprove(address(exchangeAggregator), 0);
        IERC20Upgradeable(_srcToken1).safeApprove(address(exchangeAggregator), _amount);
        IERC20Upgradeable(_srcToken2).safeApprove(address(exchangeAggregator), 0);
        IERC20Upgradeable(_srcToken2).safeApprove(address(exchangeAggregator), _amount);
        IExchangeAggregator.SwapParam[] memory _swapParams = new IExchangeAggregator.SwapParam[](2);
        _swapParams[0] = IExchangeAggregator.SwapParam({
            platform: _platform,
            method: _method,
            data: _data,
            swapDescription: _swapDesc1
        });
        _swapParams[1] = IExchangeAggregator.SwapParam({
            platform: _platform,
            method: _method,
            data: _data,
            swapDescription: _swapDesc2
        });

        exchangeAggregator.batchSwap(_swapParams);
        console2.log("after swap", _balanceOfToken(_dstToken, KEEPER));
        vm.stopPrank();
        assertGt(_balanceOfToken(_dstToken, KEEPER), _beforeDstTokenBalance);
    }

    function testSwapDAI2ETH() public {
        uint256 _amount = 10e18;
        address _srcToken = DAI_ADDRESS;
        address _dstToken = NativeToken.NATIVE_TOKEN;

        address _platform = address(testAdapter);
        uint8 _method = 0;
        bytes memory _data = new bytes(0);
        IExchangeAdapter.SwapDescription memory _swapDesc = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _srcToken,
            dstToken: _dstToken,
            receiver: KEEPER
        });

        deal(_srcToken, KEEPER, _amount);
        deal(_platform, _amount);

        vm.startPrank(KEEPER);
        uint256 _beforeDstTokenBalance = _balanceOfToken(_dstToken, KEEPER);
        console2.log("before swap", _balanceOfToken(_dstToken, KEEPER));
        IERC20Upgradeable(_srcToken).safeApprove(address(exchangeAggregator), 0);
        IERC20Upgradeable(_srcToken).safeApprove(address(exchangeAggregator), _amount);
        exchangeAggregator.swap(_platform, _method, _data, _swapDesc);
        console2.log("after swap", _balanceOfToken(_dstToken, KEEPER));
        vm.stopPrank();
        assertGt(_balanceOfToken(_dstToken, KEEPER), _beforeDstTokenBalance);
    }

    function testSwapETH2DAI() public {
        uint256 _amount = 10e18;
        address _srcToken = NativeToken.NATIVE_TOKEN;
        address _dstToken = DAI_ADDRESS;

        address _platform = address(testAdapter);
        uint8 _method = 0;
        bytes memory _data = new bytes(0);
        IExchangeAdapter.SwapDescription memory _swapDesc = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _srcToken,
            dstToken: _dstToken,
            receiver: KEEPER
        });

        deal(KEEPER, _amount);
        deal(_dstToken, _platform, _amount * 100000);

        vm.startPrank(KEEPER);
        uint256 _beforeDstTokenBalance = _balanceOfToken(_dstToken, KEEPER);
        console2.log("before swap", _balanceOfToken(_dstToken, KEEPER));
        //        IERC20Upgradeable(_srcToken).safeApprove(address(exchangeAggregator), 0);
        //        IERC20Upgradeable(_srcToken).safeApprove(address(exchangeAggregator), _amount);
        exchangeAggregator.swap{value: _amount}(_platform, _method, _data, _swapDesc);
        console2.log("after swap", _balanceOfToken(_dstToken, KEEPER));
        vm.stopPrank();
        assertGt(_balanceOfToken(_dstToken, KEEPER), _beforeDstTokenBalance);
    }

    function testBatchSwapETH2USDTUSDC() public {
        uint256 _amount = 10e18;
        address _srcToken = NativeToken.NATIVE_TOKEN;
        address _dstToken1 = USDT_ADDRESS;
        address _dstToken2 = USDC_ADDRESS;

        address _platform = address(testAdapter);
        uint8 _method = 0;
        bytes memory _data = new bytes(0);
        IExchangeAdapter.SwapDescription memory _swapDesc1 = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _srcToken,
            dstToken: _dstToken1,
            receiver: KEEPER
        });
        IExchangeAdapter.SwapDescription memory _swapDesc2 = IExchangeAdapter.SwapDescription({
            amount: _amount,
            srcToken: _srcToken,
            dstToken: _dstToken2,
            receiver: KEEPER
        });

        deal(KEEPER, _amount * 3);
        deal(_dstToken1, _platform, _amount * 1e13);
        deal(_dstToken2, _platform, _amount * 1e13);

        vm.startPrank(KEEPER);
        uint256 _beforeDstTokenBalance1 = _balanceOfToken(_dstToken1, KEEPER);
        uint256 _beforeDstTokenBalance2 = _balanceOfToken(_dstToken2, KEEPER);
        console2.log("before swap dstToken1", _balanceOfToken(_dstToken1, KEEPER));
        console2.log("before swap dstToken2", _balanceOfToken(_dstToken2, KEEPER));
        //        IERC20Upgradeable(_srcToken1).safeApprove(address(exchangeAggregator), 0);
        //        IERC20Upgradeable(_srcToken1).safeApprove(address(exchangeAggregator), _amount);
        //        IERC20Upgradeable(_srcToken2).safeApprove(address(exchangeAggregator), 0);
        //        IERC20Upgradeable(_srcToken2).safeApprove(address(exchangeAggregator), _amount);
        IExchangeAggregator.SwapParam[] memory _swapParams = new IExchangeAggregator.SwapParam[](2);
        _swapParams[0] = IExchangeAggregator.SwapParam({
            platform: _platform,
            method: _method,
            data: _data,
            swapDescription: _swapDesc1
        });
        _swapParams[1] = IExchangeAggregator.SwapParam({
            platform: _platform,
            method: _method,
            data: _data,
            swapDescription: _swapDesc2
        });

        exchangeAggregator.batchSwap{value: _amount * 2}(_swapParams);
        console2.log("after swap dstToken1", _balanceOfToken(_dstToken1, KEEPER));
        console2.log("after swap dstToken2", _balanceOfToken(_dstToken2, KEEPER));
        vm.stopPrank();
        assertGt(_balanceOfToken(_dstToken1, KEEPER), _beforeDstTokenBalance1);
        assertGt(_balanceOfToken(_dstToken2, KEEPER), _beforeDstTokenBalance2);
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
