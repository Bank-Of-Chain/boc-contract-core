/* eslint-disable */
const chai = require("chai");
const hre = require("hardhat");
const {ethers,deployments} = require("hardhat");
const {solidity} = require("ethereum-waffle");
const {utils} = require("ethers");
const { OptimalRate, SwapSide } = require("paraswap-core");
const MFC = require("../mainnet-fork-test-config");
const {topUpUsdtByAddress, topUpUsdcByAddress, topUpDaiByAddress,tranferBackUsdt,
    tranferBackUsdc,
    tranferBackDai,
    topUpWETHByAddress,
    sendEthers} = require('../../utilities/top-up-utils');
const Utils = require('../../utilities/assert-utils');
// === Constants === //
const {address} = require("hardhat/internal/core/config/config-validation");
const ERC20 = hre.artifacts.require('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');
const IEREC20Mint = artifacts.require('IEREC20Mint');
const BigNumber = require('bignumber.js');
const {
    mapKeys,
    map,
    filter,
    isEmpty,
    every
} = require("lodash");
const addresses = require("../../utilities/address-config");
const {deployMockContract} = require("@ethereum-waffle/mock-contract");

// Support BigNumber and all that with ethereum-waffle
chai.use(solidity);
const expect = chai.expect;

const AccessControlProxy = hre.artifacts.require('AccessControlProxy');
const Treasury = hre.artifacts.require('Treasury');
const ChainlinkPriceFeed = hre.artifacts.require('ChainlinkPriceFeed');
const AggregatedDerivativePriceFeed = hre.artifacts.require('AggregatedDerivativePriceFeed');
const ValueInterpreter = hre.artifacts.require("ValueInterpreter");
const TestAdapter = hre.artifacts.require("TestAdapter");
const ExchangeAggregator = hre.artifacts.require("ExchangeAggregator");
const Vault = hre.artifacts.require('Vault');
const VaultBuffer = hre.artifacts.require('VaultBuffer');
const IVault = hre.artifacts.require('IVault');
const IVaultBuffer = hre.artifacts.require('IVaultBuffer');
const IExchangeAdapter = hre.artifacts.require('IExchangeAdapter');
const VaultAdmin = hre.artifacts.require('VaultAdmin');
const Harvester = hre.artifacts.require('Harvester');
const PegToken = hre.artifacts.require('PegToken');
const Mock3CoinStrategy = hre.artifacts.require('Mock3CoinStrategy');

const CustomWstEthPriceFeed = hre.artifacts.require("CustomWstEthPriceFeed");
const CustomEthPriceFeed = hre.artifacts.require("CustomEthPriceFeed");
const CustomFakePriceFeed = hre.artifacts.require("CustomFakePriceFeed");
const UniswapV3PriceFeed = hre.artifacts.require("UniswapV3PriceFeed");
const CustomPriceFeedAggregator = hre.artifacts.require("CustomPriceFeedAggregator");

const axios = require('axios');
// const ethers = require('ethers');
const {
    send
} = require('@openzeppelin/test-helpers');

// const ExchangeTester = artifacts.require("ExchangeTester");

// const {getDefaultProvider, Contract,Wallet} = require('ethers');

const USDT = '0xdAC17F958D2ee523a2206206994597C13D831ec7';
const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const LUSD = '0x5f98805A4E8be255a32880FDeC7F6728C6568bA0';
const GUSD = '0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd';
const CRV = '0xD533a949740bb3306d119CC777fa900bA034cd52';
const ETH = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
const stETH = '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84';
const rETH = '0xae78736Cd615f374D3085123A210448E74Fc6393';
const cbETH = '0xBe9895146f7AF43049ca1c1AE358B0541Ea49704';
const sETH = '0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb';

const tokenMap = {
    USDT: {
        address: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
        decimals: 6,
    },
    USDC: {
        address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        decimals: 6,
    },
    DAI: {
        address: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
        decimals: 18,
    },
    LUSD: {
        address: '0x5f98805A4E8be255a32880FDeC7F6728C6568bA0',
        decimals: 18,
    },
    GUSD: {
        address: '0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd',
        decimals: 2,
    },
    CRV: {
        address: '0xD533a949740bb3306d119CC777fa900bA034cd52',
        decimals: 18,
    },
    ETH: {
        address: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
        decimals: 18,
    },
    stETH: {
        address: '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84',
        decimals: 18,
    },
    rETH: {
        address: '0xae78736Cd615f374D3085123A210448E74Fc6393',
        decimals: 18,
    },
    cbETH: {
        address: '0xBe9895146f7AF43049ca1c1AE358B0541Ea49704',
        decimals: 18,
    },
    sETH: {
        address: '0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb',
        decimals: 18,
    }
}


// const exchangeTester = '0x9e7F7d0E8b8F38e3CF2b3F7dd362ba2e9E82baa4';

const baseURL = 'https://api.1inch.io/v5.0/1/';
const axiosInstance = axios.create({ baseURL: baseURL });

async function getQuote(fromAsset, toAsset, amount,) {
    try {
        //console.log("====",`quote?fromTokenAddress=${fromAsset}&toTokenAddress=${toAsset}&amount=${amount}`);
        const rep = await axiosInstance.get(`quote?fromTokenAddress=${fromAsset}&toTokenAddress=${toAsset}&amount=${amount}`);
        return rep.data;
    } catch (e) {
        console.log(e);
    }
}

async function buildSwapInfo(fromAddress, fromAsset, toAsset, amount, slippage) {
    try {
        //console.log("====",`swap?fromAddress=${fromAddress}&fromTokenAddress=${fromAsset}&toTokenAddress=${toAsset}&amount=${amount}&slippage=${slippage}&disableEstimate=true&allowPartialFill=true`);
        const rep = await axiosInstance.get(`swap?fromAddress=${fromAddress}&fromTokenAddress=${fromAsset}&toTokenAddress=${toAsset}&amount=${amount}&slippage=${slippage}&disableEstimate=true&allowPartialFill=true`);
        return rep.data;
    } catch (error) {
        console.log(error);
    }
}

async function swap(contractAccount, from, to, platformType) {

    const fromAmount = await balanceOf(from, contractAccount);//new BigNumber(500_000_000_000_000_000);

    const quoteInfo = await getQuote(from, to, fromAmount.toString());
    const fromSymbol = quoteInfo.fromToken.symbol;
    const toSymbol = quoteInfo.toToken.symbol;
    console.log('[Quote] %s %s ==> %s %s', quoteInfo.fromTokenAmount, fromSymbol, quoteInfo.toTokenAmount, toSymbol);
    console.log('estimatedGas:',quoteInfo.estimatedGas);
    

    const swapInfo = await buildSwapInfo(contractAccount, from, to, fromAmount.toString(), 50);
    const protocols = swapInfo.protocols;

    for (let i = 0; i < protocols.length; i++) {
        const fegments = protocols[i];
        console.log('fegment:', i + 1);;
        for (let j = 0; j < fegments.length; j++) {
            for (const pool of fegments[j]) {
                console.log('  swap %s% %s => %s at %s', pool.part, await getSymbol(pool.fromTokenAddress), await getSymbol(pool.toTokenAddress), pool.name);
            }
        }
    }

    const provider = ethers.provider;
    let vault = new ethers.Contract(contractAccount, Vault.abi, provider);
    let returnAmount = await vault.callStatic.exchange(from, to, fromAmount.toString(), swapInfo.tx.data,platformType);
    console.log("returnAmount is ===",returnAmount.toString());

    vault = await Vault.at(contractAccount);
    let tx = await vault.exchange(from, to, fromAmount.toString(), swapInfo.tx.data,platformType);


    console.log('after swap %s:%s,%s:%s', fromSymbol,
        await balanceOf(from, contractAccount),
        'USDT',
        await balanceOf(to, contractAccount));
}



async function getSymbol(_asset) {
    if (_asset.toLowerCase() == ETH.toLowerCase()) {
        return 'ETH';
    } else {
        const erc20Token = await ERC20.at(_asset);
        return erc20Token.symbol();
    }
}

async function balanceOf(_asset, _account) {
    if (_asset == ETH) {
        const provider = ethers.provider;
        // console.log('balance=', (await provider.getBalance(_account)).toString());
        return await provider.getBalance(_account);
    } else {
        const erc20Token = await ERC20.at(_asset);
        // const decimals = new BigNumber(await erc20Token.decimals());

        return erc20Token.balanceOf(_account);
    }
}

// paraswap exchange
const baseURLParaswap = 'https://apiv5.paraswap.io/';
const axiosInstancePara = axios.create({ baseURL: baseURLParaswap });

const PARTNER = "chucknorris";
const SLIPPAGE = 15; // 1%



const getRate = async (
    srcToken,
    destToken,
    srcAmount,
    partner = PARTNER
) => {
    const queryParams = {
        srcToken: srcToken.address,
        destToken: destToken.address,
        srcDecimals: srcToken.decimals.toString(),
        destDecimals: destToken.decimals.toString(),
        amount: srcAmount,
        side: SwapSide.SELL,
        network: '1',
        partner
    };

    const searchString = new URLSearchParams(queryParams);

    // const pricesURL = `${baseURLParaswap}prices/?${searchString}`;
    // console.log("GET /price URL", pricesURL);

    const rep = await axiosInstancePara.get(`prices/?${searchString}&excludeDEXS=ParaSwapPool,ParaSwapLimitOrders`);

    // const result = await axios.get(pricesURL);
    return rep.data.priceRoute;
};

const buildSwap = async ({
    srcToken,
    destToken,
    srcAmount,
    minAmount,
    priceRoute,
    userAddress,
    receiver,
}) => {
    // const txURL = `${apiURL}/transactions/${networkID}`;

    const txConfig = {
        priceRoute,
        srcToken: srcToken.address,
        srcDecimals: srcToken.decimals,
        destToken: destToken.address,
        destDecimals: destToken.decimals,
        srcAmount,
        destAmount: minAmount,
        userAddress,
        receiver,
    };
    // console.log('txConfig:',JSON.stringify(txConfig));
    const rep = await axiosInstancePara.post('transactions/1?ignoreChecks=true', txConfig);
    return rep.data.data;
};

async function swapOnPara(contractAccount, from, to, platformType) {

    const fromAmount = await balanceOf(from.address, contractAccount);//new BigNumber(500_000_000_000_000_000);

    const priceRoute = await getRate(from, to, fromAmount.toString());
    // console.log('priceRoute:', priceRoute);
    const minAmount = new BigNumber(priceRoute.destAmount)
        .times(1 - SLIPPAGE / 100)
        .toFixed(0);

    console.log('before swap %s:%s,%s:%s', await getSymbol(from.address),
        await balanceOf(from.address, contractAccount),
        await getSymbol(to.address),
        await balanceOf(to.address, contractAccount));

    const txParams = await buildSwap({
        srcToken: from,
        destToken: to,
        srcAmount: fromAmount.toString(),
        minAmount: minAmount,
        priceRoute,
        userAddress: contractAccount,
        receiver: contractAccount,
    });
    // console.log('txParams:', txParams);

    const vault = await Vault.at(contractAccount);
    await vault.exchange(from.address, to.address, fromAmount.toString(), txParams, platformType);

    console.log('after swap %s:%s,%s:%s', await getSymbol(from.address),
        await balanceOf(from.address, contractAccount),
        await getSymbol(to.address),
        await balanceOf(to.address, contractAccount));
}

describe("Vault", function () {
    this.timeout(300000);
    let accounts;
    let governance;
    let farmer1;
    let farmer2;
    let keeper;
    let token;
    let tokenDecimals;
    let usdiDecimals;
    let vaultBufferDecimals;
    let depositAmount
    let daiDepositAmount
    let daiDecimals;
    let usdcDepositAmount
    let usdcDecimals;
    let treasury;
    let testAdapter;
    let mockS3CoinStrategy;

    // Core protocol contracts
    let usdi;
    let pegToken;
    let vault;
    let vaultBuffer;
    let iVault;
    let vaultAdmin;
    let underlying;
    let usdcToken;
    let daiToken;
    let underlyingAddress;
    let valueInterpreter;
    let exchangeAggregator;
    let exchangePlatformAdapters;

    before(async function () {
        this.timeout(600000);
        usdiDecimals = 18;
        vaultBufferDecimals = 18;
        underlyingAddress = MFC.USDT_ADDRESS;
        token = await ERC20.at(MFC.USDT_ADDRESS);
        underlying = await ERC20.at(underlyingAddress);
        usdcToken = await ERC20.at(MFC.USDC_ADDRESS);
        daiToken = await ERC20.at(MFC.DAI_ADDRESS);
        tokenDecimals = new BigNumber(await token.decimals());
        usdcDecimals = new BigNumber(await usdcToken.decimals());
        daiDecimals = new BigNumber(await daiToken.decimals());
        depositAmount = new BigNumber(10).pow(tokenDecimals).multipliedBy(1000);
        usdcDepositAmount = new BigNumber(10).pow(usdcDecimals).multipliedBy(1000);
        daiDepositAmount = new BigNumber(10).pow(daiDecimals).multipliedBy(1000);
        await ethers.getSigners().then((resp) => {
            accounts = resp;
            governance = accounts[0].address;
            farmer1 = accounts[1].address;
            farmer2 = accounts[2].address;
            keeper = accounts[19].address;
            dripper = accounts[18];
        });
        await tranferBackUsdt(farmer1);
        await topUpUsdtByAddress(depositAmount, farmer1);
        await tranferBackUsdc(farmer1);
        await topUpUsdcByAddress(usdcDepositAmount, farmer1);
        await tranferBackDai(farmer1);
        await topUpDaiByAddress(daiDepositAmount, farmer1);
        await tranferBackUsdt(farmer2);
        await topUpUsdtByAddress(depositAmount, farmer2);
        await tranferBackUsdc(farmer2);
        await topUpUsdcByAddress(usdcDepositAmount, farmer2);
        await tranferBackDai(farmer2);
        await topUpDaiByAddress(daiDepositAmount, farmer2);

        console.log("deploy Vault");
        vault = await Vault.new();

        console.log("deploy accessControlProxy");
        const accessControlProxy = await AccessControlProxy.new();
        accessControlProxy.initialize(governance, governance, vault.address, keeper);

        console.log("deploy ChainlinkPriceFeed");
        // oracle
        const primitives = new Array();
        const aggregators = new Array();
        const heartbeats = new Array();
        const rateAssets = new Array();
        for (const key in MFC.CHAINLINK.aggregators) {
            const value = MFC.CHAINLINK.aggregators[key];
            primitives.push(value.primitive);
            aggregators.push(value.aggregator);
            heartbeats.push(value.heartbeat);
            rateAssets.push(value.rateAsset);
        }
        const basePeggedPrimitives = new Array();
        const basePeggedRateAssets = new Array();
        for (const key in MFC.CHAINLINK.basePegged) {
            const value = MFC.CHAINLINK.basePegged[key];
            basePeggedPrimitives.push(value.primitive);
            basePeggedRateAssets.push(value.rateAsset);
        }
        const chainlinkPriceFeed = await ChainlinkPriceFeed.new(
            MFC.CHAINLINK.ETH_USD_AGGREGATOR,
            MFC.CHAINLINK.ETH_USD_HEARTBEAT,
            primitives,
            aggregators,
            heartbeats,
            rateAssets,
            basePeggedPrimitives,
            basePeggedRateAssets,
            accessControlProxy.address
        );
        const ROCKET_ETH_WETH_POOL_ADDRESS = '0xa4e0faA58465A2D369aa21B3e42d43374c6F9613';
        const SETH2_WETH_POOL_ADDRESS = '0x7379e81228514a1D2a6Cf7559203998E20598346';

        const SETH2_DURATION = 3600;
        const ROCKET_ETH_DURATION = 3600;

        const primitives2 = new Array();
        primitives2.push(MFC.rocketPoolETH_ADDRESS);
        primitives2.push(MFC.sETH2_ADDRESS);
        const pools = new Array();
        pools.push(ROCKET_ETH_WETH_POOL_ADDRESS);
        pools.push(SETH2_WETH_POOL_ADDRESS);
        const durations = new Array();
        durations.push(ROCKET_ETH_DURATION);
        durations.push(SETH2_DURATION);
        const uniswapV3PriceFeed = await UniswapV3PriceFeed.new(
            accessControlProxy.address,
            MFC.CHAINLINK.ETH_USD_AGGREGATOR,
            primitives2,
            pools,
            durations
        );

        const customWstEthPriceFeed = await CustomWstEthPriceFeed.new();

        const customEthPriceFeed = await CustomEthPriceFeed.new();

        const customFakePriceFeed = await CustomFakePriceFeed.new();

        const baseAssets = [];
        baseAssets.push(MFC.wstETH_ADDRESS);
        baseAssets.push(MFC.ETH_ADDRESS);
        baseAssets.push(MFC.sETH_ADDRESS);
        const _customPriceFeeds = [];
        _customPriceFeeds[0] = customWstEthPriceFeed.address;
        _customPriceFeeds[1] = customEthPriceFeed.address;
        _customPriceFeeds[2] = customFakePriceFeed.address;
        let customPriceFeedAggregator = await CustomPriceFeedAggregator.new(
            baseAssets,
            _customPriceFeeds,
            accessControlProxy.address,
        );

        console.log('deploy ValueInterpreter');
        valueInterpreter = await ValueInterpreter.new(chainlinkPriceFeed.address, uniswapV3PriceFeed.address, customPriceFeedAggregator.address,accessControlProxy.address);

        console.log('deploy TestAdapter');
        testAdapter = await TestAdapter.new(valueInterpreter.address);

        console.log('deploy ExchangeAggregator');
        exchangeAggregator = await ExchangeAggregator.new([testAdapter.address], accessControlProxy.address);
        const adapters = await exchangeAggregator.getExchangeAdapters();
        exchangePlatformAdapters = {};
        for (let i = 0; i < adapters._identifiers.length; i++) {
            exchangePlatformAdapters[adapters._identifiers[i]] = adapters._exchangeAdapters[i];
        }

        // console.log('deploy USDi');
        // usdi = await USDi.new();
        // await usdi.initialize('USDi', 'USDi', 18, vault.address, accessControlProxy.address);

        console.log('deploy PegToken');
        pegToken = await PegToken.new();
        await pegToken.initialize('USD Peg Token', 'USDi', 18, vault.address, accessControlProxy.address);

        console.log('vault Buffer');
        vaultBuffer = await VaultBuffer.new();
        await vaultBuffer.initialize('USD Peg Token Ticket', 'tUSDi', vault.address, pegToken.address,accessControlProxy.address);

        console.log('deploy Treasury');
        // treasury
        treasury = await Treasury.new();
        await treasury.initialize(accessControlProxy.address);

        await vault.initialize(accessControlProxy.address, treasury.address, valueInterpreter.address, 0);
        vaultAdmin = await VaultAdmin.new();
        await vault.setAdminImpl(vaultAdmin.address, { from: governance });

        const harvester = await Harvester.new();
        
        await harvester.initialize(accessControlProxy.address, treasury.address, vault.address,vault.address);

        console.log("USDT_PRICE:", new BigNumber(await valueInterpreter.price(MFC.USDT_ADDRESS)).toFixed());
        console.log("USDT_CALC:", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.USDT_ADDRESS, 10 ** 6)).toFixed());
        console.log("USDC_PRICE:", new BigNumber(await valueInterpreter.price(MFC.USDC_ADDRESS)).toFixed());
        console.log("USDC_CALC:", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.USDC_ADDRESS, 10 ** 6)).toFixed());
        console.log("DAI_PRICE:", new BigNumber(await valueInterpreter.price(MFC.DAI_ADDRESS)).toFixed());
        console.log("DAI_CALC:", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.DAI_ADDRESS, new BigNumber(10 ** 18))).toFixed());
        console.log("DAI_CALC(2):", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.DAI_ADDRESS, new BigNumber(2))).toFixed());
        console.log('mockS3CoinStrategy USDi');
        // Strategy
        let mock3CoinStrategy = await Mock3CoinStrategy.new();
        let _wants = [];
        // USDT
        _wants[0] = MFC.USDT_ADDRESS;
        // USDC
        _wants[1] = MFC.USDC_ADDRESS;
        // DAI
        _wants[2] = MFC.DAI_ADDRESS;
        let _ratios = [];
        _ratios[0] = 1;
        _ratios[1] = 2;
        _ratios[2] = 4;
        await mock3CoinStrategy.initialize(vault.address, harvester.address,_wants,_ratios);

        iVault = await IVault.at(vault.address);
        // await iVault.setUSDiAddress(usdi.address);
        await iVault.setVaultBufferAddress(vaultBuffer.address);

        await expect(
            iVault.setVaultBufferAddress(vaultBuffer.address)
        ).to.be.revertedWith("VaultBuffer ad has been set");
        await iVault.setPegTokenAddress(pegToken.address);

        await expect(
            iVault.setPegTokenAddress(pegToken.address)
        ).to.be.revertedWith("PegToken ad has been set");
        // await iVault.setRebaseThreshold(1);
        // await iVault.setUnderlyingUnitsPerShare(new BigNumber(10).pow(18).toFixed());
        // await iVault.setMaxTimestampBetweenTwoReported(604800, {from: governance});
        console.log("maxTimestampBetweenTwoReported:",new BigNumber(await iVault.maxTimestampBetweenTwoReported()).toFixed());
    });

    it('Verify: Vault can add and remove Assets normally', async function () {
        const preLength = (await iVault.getSupportAssets()).length
        console.log('Number of Assets before adding=', preLength);
        await iVault.addAsset(underlyingAddress, {from: governance});
        const lastLength = (await iVault.getSupportAssets()).length
        console.log('Number of Assets after adding=', lastLength);
        Utils.assertBNGt(lastLength, preLength);
        await iVault.removeAsset(underlyingAddress, {from: governance});
        const removeLastLength = (await iVault.getSupportAssets()).length
        console.log('Number of Assets after removal=', removeLastLength);
        Utils.assertBNGt(lastLength, removeLastLength);
    });

    it('Verify: Vault can add and remove all policies normally', async function () {
        let addToVaultStrategies = new Array();
        addToVaultStrategies.push({
            strategy: mock3CoinStrategy.address,
            profitLimitRatio: 100,
            lossLimitRatio: 100
        });

        await iVault.addStrategies(addToVaultStrategies, {from: governance});
        let strategyAddresses = await iVault.getStrategies();
        console.log('Number of policies before adding=', strategyAddresses.length);
        await iVault.removeStrategies(strategyAddresses, {from: governance});
        let length = (await iVault.getStrategies()).length;
        console.log('Number of policies after removal=', length);
        Utils.assertBNEq(length, 0);

        await iVault.addStrategies(addToVaultStrategies, {from: governance});
        strategyAddresses = await iVault.getStrategies();
        console.log('Number of policies before adding=', strategyAddresses.length);
        await iVault.forceRemoveStrategy(mock3CoinStrategy.address, {from: governance});
        length = (await iVault.getStrategies()).length;
        console.log('Number of policies after removal=', length);
        Utils.assertBNEq(length, 0);
    });

    it('Verify：Vault can be invested normally', async function () {
        await iVault.addAsset(MFC.DAI_ADDRESS, {from: governance});
        await iVault.addAsset(MFC.USDC_ADDRESS, {from: governance});
        await iVault.addAsset(underlyingAddress, {from: governance});

        let _assets = new Array();
        _assets.push(underlyingAddress);
        let _amounts = new Array();
        _amounts.push(depositAmount);
        let _minimumUsdiAmount = 0;
        console.log("Balance of usdt of vault before investing:", new BigNumber(await underlying.balanceOf(iVault.address)).div(10 ** tokenDecimals).toFixed());
        console.log("Balance of usdt of vaultBuffer before investing", new BigNumber(await underlying.balanceOf(vaultBuffer.address)).div(10 ** tokenDecimals).toFixed());
        console.log("Balance of usdi of farmer1 before investing:", new BigNumber(await pegToken.balanceOf(farmer1)).div(10 ** usdiDecimals).toFixed());
        console.log("Balance of tUSDi of farmer1 before investing:", new BigNumber(await vaultBuffer.balanceOf(farmer1)).div(10 ** vaultBufferDecimals).toFixed());
        console.log("Balance of usdt of farmer1 before investing:", new BigNumber(await underlying.balanceOf(farmer1)).div(10 ** tokenDecimals).toFixed());

        await underlying.approve(iVault.address, 0, {
            from: farmer1
        });
        await underlying.approve(iVault.address, depositAmount, {
            from: farmer1
        });

        await iVault.mint(_assets, _amounts, _minimumUsdiAmount, {from: farmer1});
        const balance = new BigNumber(await vaultBuffer.balanceOf(farmer1)).toFixed();

        console.log("Balance of usdt of vault after investment:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("Balance of usdt of vaultBuffer after investment:%s", new BigNumber(await underlying.balanceOf(vaultBuffer.address)).toFixed());
        console.log("Balance of tUSDi of vaultBuffer after investment:%s", balance);
        console.log("Balance of usdt of farmer1 after investment:%s", new BigNumber(await underlying.balanceOf(farmer1)).toFixed());
        console.log("Total assets in vault cache pool after investment:%s,Total assets(include vault buffer):%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

        Utils.assertBNGt(balance, 0);
    });


    it('Verify：Vault can be invested in other assets normally', async function () {
        let _assets = new Array();
        _assets.push(MFC.USDC_ADDRESS);
        _assets.push(MFC.DAI_ADDRESS);
        let _amounts = new Array();
        _amounts.push(usdcDepositAmount);
        _amounts.push(daiDepositAmount);

        await usdcToken.approve(iVault.address, 0, {
            from: farmer1
        });
        await usdcToken.approve(iVault.address, usdcDepositAmount, {
            from: farmer1
        });

        await daiToken.approve(iVault.address, 0, {
            from: farmer1
        });
        await daiToken.approve(iVault.address, daiDepositAmount, {
            from: farmer1
        });

        console.log("Balance of usdc of farmer1 before investing:%s", new BigNumber(await usdcToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of dai of farmer1 before investing:%s", new BigNumber(await daiToken.balanceOf(farmer1)).toFixed());

        await iVault.mint(_assets, _amounts, 0, {from: farmer1});

        console.log("totalAssets after investment:%s,total vault:%s", new BigNumber(await iVault.totalAssets()).toFixed(), new BigNumber(await iVault.totalValue()).toFixed());
        console.log("totalDebt after investment:%s,totalValueInStrategies：%s", new BigNumber(await iVault.totalDebt()).toFixed(), new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        console.log("valueOfTrackedTokens after investmen:%s,totalValueInVault：%s", new BigNumber(await iVault.valueOfTrackedTokens()).toFixed(), new BigNumber(await iVault.totalValueInVault()).toFixed());
        console.log("valueOfTrackedTokensIncludeVaultBuffer after investmen:%s,totalAssetsIncludeVaultBuffer：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

        // Charge 100 million
        const amount = new BigNumber(10).pow(14);
        await topUpUsdtByAddress(amount, testAdapter.address);
        await topUpUsdcByAddress(amount, testAdapter.address);
        await topUpDaiByAddress(amount, testAdapter.address);

        // await iVault.setTrusteeFeeBps(1000, {from: governance});

        await iVault.setRebaseThreshold(1, {from: governance});

        console.log('rebaseThreshold: %s', (await iVault.rebaseThreshold()).toString());

        //startAdjustPosition
        const tx = await iVault.startAdjustPosition({from: keeper});
        const gasUsed = tx.receipt.gasUsed;
        console.log('startAdjustPosition gasUsed: %d', gasUsed);

        const beforeBalance = new BigNumber(await usdcToken.balanceOf(farmer1)).div(10 ** tokenDecimals).toFixed();

        console.log("Balance of usdt of vault after start adjust position:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("Balance of usdc of vault after start adjust position:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault after start adjust position:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of usdi of farmer1 after start adjust position:%s", new BigNumber(await pegToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of usdt of farmer1 after start adjust position:%s", new BigNumber(await underlying.balanceOf(farmer1)).toFixed());
        console.log("Balance of dai of farmer1 after start adjust position:%s", new BigNumber(await daiToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of usdc of farmer1 after start adjust position:%s", beforeBalance);
        console.log("valueOfTrackedTokensIncludeVaultBuffer after start adjust position:%s,totalAssetsIncludeVaultBuffer：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

    });

    it('Verify：Vault can be lend normally', async function () {
        let addToVaultStrategies = new Array();
        let withdrawQueque = new Array();
        addToVaultStrategies.push({
            strategy: mock3CoinStrategy.address,
            profitLimitRatio: 100,
            lossLimitRatio: 100
        });
        withdrawQueque.push(mock3CoinStrategy.address);
        await iVault.addStrategies(addToVaultStrategies, {from: governance});
        await iVault.setWithdrawalQueue(withdrawQueque, {from: governance});

        const beforeUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        console.log("Balance of usdt of vault before lend:%s", beforeUsdt);
        console.log("Balance of usdc of vault before lend:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault before lend:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("(usdt,usdc,dai)=(%s,%s,%s)", depositAmount.toFixed(), usdcDepositAmount.toFixed(), daiDepositAmount.toFixed());
        let tokens = [MFC.USDT_ADDRESS, MFC.USDC_ADDRESS, MFC.DAI_ADDRESS];
        let amounts = [depositAmount.toFixed(), usdcDepositAmount.toFixed(), daiDepositAmount.toFixed()];

        await iVault.lend(mock3CoinStrategy.address, tokens, amounts);

        console.log("totalAssets after lend:%s,totalValue：%s", new BigNumber(await iVault.totalAssets()).toFixed(), new BigNumber(await iVault.totalValue()).toFixed());
        console.log("totalDebt after lend:%s,totalValueInStrategies：%s", new BigNumber(await iVault.totalDebt()).toFixed(), new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        console.log("valueOfTrackedTokens after lend:%s,totalValueInVault：%s", new BigNumber(await iVault.valueOfTrackedTokens()).toFixed(), new BigNumber(await iVault.totalValueInVault()).toFixed());
        console.log("valueOfTrackedTokensIncludeVaultBuffer after lend:%s,totalAssetsIncludeVaultBuffer：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

        const afterUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        console.log("Balance of usdt of vault after lend:%s", afterUsdt);
        console.log("Balance of usdc of vault after lend:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault after lend:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        Utils.assertBNGt(beforeUsdt, afterUsdt);

        const tx = await iVault.endAdjustPosition({from: keeper});
        const gasUsed = tx.receipt.gasUsed;
        console.log('endAdjustPosition gasUsed: %d', gasUsed);

        console.log('start distributeWhenDistributing');
        await vaultBuffer.distributeWhenDistributing({from: keeper});
        console.log('end distributeWhenDistributing');

        console.log("Balance of usdi of farmer1 after end adjust position:%s", new BigNumber(await pegToken.balanceOf(farmer1)).toFixed());
        console.log("underlyingUnitsPerShare after end adjust position:%s", new BigNumber(await iVault.underlyingUnitsPerShare()).toFixed());
        console.log("Balance of share of farmer1 after end adjust position:%s", new BigNumber(await pegToken.sharesOf(farmer1)).toFixed());
        console.log("valueOfTrackedTokensIncludeVaultBuffer after end adjust position:%s,totalAssetsIncludeVaultBuffer：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

        const _amount = new BigNumber(await pegToken.balanceOf(farmer1)).div(4).multipliedBy(1).toFixed();
        const _toAsset = MFC.USDC_ADDRESS;
        console.log("withdraw asset:USDC");
        console.log("Number of usdi withdraw:%s", new BigNumber(_amount).toFixed());

        const beforeBalance = new BigNumber(await usdcToken.balanceOf(farmer1)).toFixed();

        let _redeemFeeBps = await iVault.redeemFeeBps();
        let _trusteeFeeBps = await iVault.trusteeFeeBps();
        await iVault.burn(_amount, 0, _redeemFeeBps, _trusteeFeeBps, {from: farmer1});

        const afterBalance = new BigNumber(await usdcToken.balanceOf(farmer1)).toFixed();

        console.log("Balance of usdt of vault after withdraw:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("Balance of usdc of vault after withdraw:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault after withdraw:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of usdi of farmer1 after withdraw:%s", new BigNumber(await pegToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of usdt of farmer1 after withdraw:%s", new BigNumber(await underlying.balanceOf(farmer1)).toFixed());
        console.log("Balance of dai of farmer1 after withdraw:%s", new BigNumber(await daiToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of usdc of farmer1 after withdraw:%s", afterBalance);
        Utils.assertBNGt(afterBalance, beforeBalance);

        console.log("valueOfTrackedTokensIncludeVaultBuffer after withdraw:%s,totalAssetsIncludeVaultBuffer：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

        console.log("valueOfTrackedTokensIncludeVaultBuffer after withdraw:%s,totalAssetsIncludeVaultBuffer：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());
        const usdcIEREC20Mint = await IEREC20Mint.at(MFC.USDC_ADDRESS);
        await usdcIEREC20Mint.transfer(mock3CoinStrategy.address, new BigNumber(await usdcToken.balanceOf(farmer1)).div(1000).toFixed(), {
            from: farmer1,
        });
        console.log("valueOfTrackedTokensIncludeVaultBuffer after transfer usdc to vault:%s,totalAssetsIncludeVaultBuffer：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

    });

    it('Verify：new funds deposit to vault', async function () {
        let _assets = new Array();
        _assets.push(MFC.USDT_ADDRESS);
        _assets.push(MFC.USDC_ADDRESS);
        _assets.push(MFC.DAI_ADDRESS);
        let _amounts = new Array();
        _amounts.push(depositAmount);
        _amounts.push(usdcDepositAmount);
        _amounts.push(daiDepositAmount);

        await underlying.approve(iVault.address, 0, {
            from: farmer2
        });
        await underlying.approve(iVault.address, depositAmount, {
            from: farmer2
        });

        await usdcToken.approve(iVault.address, 0, {
            from: farmer2
        });
        await usdcToken.approve(iVault.address, usdcDepositAmount, {
            from: farmer2
        });

        await daiToken.approve(iVault.address, 0, {
            from: farmer2
        });
        await daiToken.approve(iVault.address, daiDepositAmount, {
            from: farmer2
        });

        console.log("Balance of usdc of farmer2 before deposit:%s", new BigNumber(await usdcToken.balanceOf(farmer2)).toFixed());
        console.log("Balance of dai of farmer2 before deposit:%s", new BigNumber(await daiToken.balanceOf(farmer2)).toFixed());
        console.log("Balance of usdt of farmer2 before deposit:%s", new BigNumber(await underlying.balanceOf(farmer2)).toFixed());

        console.log("adjustPositionPeriod:%s",await iVault.adjustPositionPeriod());

        console.log("Balance of usdt of vault before deposit:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("Balance of usdc of vault before deposit:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault before deposit:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        await iVault.mint(_assets, _amounts, 0, {from: farmer2});
        console.log("Balance of usdt of vault after deposit:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("Balance of usdc of vault after deposit:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault after deposit:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());

        console.log("Balance of usdc of farmer2 after deposit:%s", new BigNumber(await usdcToken.balanceOf(farmer2)).toFixed());
        console.log("Balance of dai of farmer2 after deposit:%s", new BigNumber(await daiToken.balanceOf(farmer2)).toFixed());
        console.log("Balance of usdt of farmer2 after deposit:%s", new BigNumber(await underlying.balanceOf(farmer2)).toFixed());
        console.log("Balance of tusdi of farmer2 after deposit:%s", new BigNumber(await vaultBuffer.balanceOf(farmer2)).toFixed());

        console.log("totalAssets after deposit:%s,totalValue：%s", new BigNumber(await iVault.totalAssets()).toFixed(), new BigNumber(await iVault.totalValue()).toFixed());
        console.log("totalDebt after deposit:%s,totalValueInStrategies：%s", new BigNumber(await iVault.totalDebt()).toFixed(), new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        console.log("valueOfTrackedTokens after deposit:%s,totalValueInVault：%s", new BigNumber(await iVault.valueOfTrackedTokens()).toFixed(), new BigNumber(await iVault.totalValueInVault()).toFixed());
        console.log("valueOfTrackedTokensIncludeVaultBuffer after deposit:%s,totalAssetsIncludeVaultBuffer：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

        console.log("before startAdjustPosition PegTokenPrice:%s", new BigNumber(await iVault.getPegTokenPrice()).toFixed());

        //startAdjustPosition
        console.log("startAdjustPosition");
        let tx =  await iVault.startAdjustPosition({from: keeper});
        console.log("after startAdjustPosition PegTokenPrice:%s", new BigNumber(await iVault.getPegTokenPrice()).toFixed());
        let gasUsed = tx.receipt.gasUsed;
        console.log('startAdjustPosition gasUsed: %d', gasUsed);
        console.log("Balance of usdt of vault before redeem:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("Balance of usdc of vault before redeem:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault before redeem:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("(amount,totalDebt)=(%s,%s)", new BigNumber(await iVault.totalDebt()).div(5).toFixed(),new BigNumber(await iVault.totalDebt()).toFixed());
        let beforeUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        console.log("redeem amount: %s",new BigNumber(await iVault.totalDebt()).div(5).toFixed())
        tx =  await iVault.redeem(mock3CoinStrategy.address, new BigNumber(await iVault.totalDebt()).div(5).toFixed(), 0);
        gasUsed = tx.receipt.gasUsed;
        console.log('redeem gasUsed: %d', gasUsed);
        let afterUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();

        console.log("Balance of usdt of vault after redeem:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("Balance of usdc of vault after redeem:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai vault after redeem:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());

        console.log("valueOfTrackedTokens after redeem:%s", new BigNumber(await iVault.valueOfTrackedTokens()).toFixed());
        console.log("totalAssets  after redeem:%s", new BigNumber(await iVault.totalAssets()).toFixed());
        Utils.assertBNGt(afterUsdt, beforeUsdt);

        beforeUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        console.log("Balance of usdt of vault before lend:%s", beforeUsdt);
        console.log("Balance of usdc of vault before lend:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault before lend:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("(usdt,usdc,dai)=(%s,%s,%s)", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed(), new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed(), new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        let tokens = [MFC.USDT_ADDRESS, MFC.USDC_ADDRESS, MFC.DAI_ADDRESS];
        let amounts = [new BigNumber(await underlying.balanceOf(iVault.address)).toFixed(), new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed(), new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed()];

        await iVault.lend(mock3CoinStrategy.address, tokens, amounts);

        console.log("totalAssets after lend:%s,totalValue：%s", new BigNumber(await iVault.totalAssets()).toFixed(), new BigNumber(await iVault.totalValue()).toFixed());
        console.log("totalDebt after lend:%s,totalValueInStrategies：%s", new BigNumber(await iVault.totalDebt()).toFixed(), new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        console.log("valueOfTrackedTokens after lend:%s,totalValueInVault：%s", new BigNumber(await iVault.valueOfTrackedTokens()).toFixed(), new BigNumber(await iVault.totalValueInVault()).toFixed());

        afterUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        console.log("Balance of usdt of vault after lend:%s", afterUsdt);
        console.log("Balance of usdc of vault after lend:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault after lend:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        Utils.assertBNGt(beforeUsdt, afterUsdt);

        console.log("before endAdjustPosition PegTokenPrice:%s", new BigNumber(await iVault.getPegTokenPrice()).toFixed());
        tx = await iVault.endAdjustPosition({from: keeper});
        gasUsed = tx.receipt.gasUsed;
        console.log('endAdjustPosition gasUsed: %d', gasUsed);
        console.log("after endAdjustPosition PegTokenPrice:%s", new BigNumber(await iVault.getPegTokenPrice()).toFixed());

        console.log('start distributeWhenDistributing');
        await vaultBuffer.distributeWhenDistributing({from: keeper});
        console.log('end distributeWhenDistributing');

        console.log("Balance of usdi of farmer1 after end adjust position:%s", new BigNumber(await pegToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of usdi of farmer2 after end adjust position:%s", new BigNumber(await pegToken.balanceOf(farmer2)).toFixed());
        console.log("valueOfTrackedTokensIncludeVaultBuffer after end adjust position:%s,totalAssetsIncludeVaultBuffer：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());
    });

    it('Verify：report by strategy and keeper', async function (){
       const usdcIEREC20Mint = await IEREC20Mint.at(MFC.USDC_ADDRESS);
       let estimatedTotalAssets = await mock3CoinStrategy.estimatedTotalAssets();
       let strategyParams =  await iVault.strategies(mock3CoinStrategy.address);
       const firstTotalDebt = strategyParams.totalDebt;
       console.log("before reportWithoutClaim",estimatedTotalAssets.toString(),strategyParams.totalDebt.toString());
        await usdcIEREC20Mint.transfer(mock3CoinStrategy.address, new BigNumber(1000).toFixed(), {
            from: farmer1,
        });
       await mock3CoinStrategy.reportWithoutClaim();
       estimatedTotalAssets = await mock3CoinStrategy.estimatedTotalAssets();
       strategyParams =  await iVault.strategies(mock3CoinStrategy.address);
       const secondTotalDebt = strategyParams.totalDebt;
       console.log("after reportWithoutClaim",estimatedTotalAssets.toString(),strategyParams.totalDebt.toString());
       await usdcIEREC20Mint.transfer(mock3CoinStrategy.address, new BigNumber(1000).toFixed(), {
            from: farmer1,
        });
        await iVault.reportByKeeper([mock3CoinStrategy.address]);
        estimatedTotalAssets = await mock3CoinStrategy.estimatedTotalAssets();
        strategyParams =  await iVault.strategies(mock3CoinStrategy.address);
        const thirdTotalDebt = strategyParams.totalDebt;
        console.log("after reportByKeeper",estimatedTotalAssets.toString(),strategyParams.totalDebt.toString());
        Utils.assertBNGt(secondTotalDebt, firstTotalDebt);
        Utils.assertBNGt(thirdTotalDebt, secondTotalDebt);
    });

    it('Verify：burn from strategy', async function (){
        console.log("before rebase PegTokenPrice:%s", new BigNumber(await iVault.getPegTokenPrice()).toFixed());
        let _trusteeFeeBps = await iVault.trusteeFeeBps();
        await iVault.rebase(_trusteeFeeBps);
        console.log("after rebase PegTokenPrice:%s", new BigNumber(await iVault.getPegTokenPrice()).toFixed());
        console.log("totalValueInStrategies before withdraw: %s",new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        console.log("totalAssets before withdraw: %s",new BigNumber(await iVault.totalAssets()).toFixed());
        console.log("Balance of usdi of farmer1 before withdraw: %s", new BigNumber(await pegToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of usdi of farmer2 before withdraw: %s", new BigNumber(await pegToken.balanceOf(farmer2)).toFixed());
        let _amount =  new BigNumber(await pegToken.balanceOf(farmer1)).toFixed();

        let _redeemFeeBps = await iVault.redeemFeeBps();
        await iVault.burn(_amount, 0, _redeemFeeBps, _trusteeFeeBps, {from: farmer1});
        console.log("totalValueInStrategies after farmer1 withdraw: %s",new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        _amount =  new BigNumber(await pegToken.balanceOf(farmer2)).minus(new BigNumber(10).pow(18)).toFixed();
        await iVault.burn(_amount, 0, _redeemFeeBps, _trusteeFeeBps, {from: farmer2});
        let totalValueInStrategies = new BigNumber(await iVault.totalValueInStrategies()).toFixed();
        console.log("totalValueInStrategies after withdraw: %s",totalValueInStrategies);
        console.log("totalAssets after withdraw: %s",new BigNumber(await iVault.totalAssets()).toFixed());
        console.log("Balance of usdi of farmer1 after withdraw: %s", new BigNumber(await pegToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of usdi of farmer2 after withdraw: %s", new BigNumber(await pegToken.balanceOf(farmer2)).toFixed());

        Utils.assertBNGt(totalValueInStrategies, 0);
        await iVault.burn(new BigNumber(await pegToken.balanceOf(farmer2)), 0, _redeemFeeBps, _trusteeFeeBps, {from: farmer2});;
        totalValueInStrategies = new BigNumber(await iVault.totalValueInStrategies()).toFixed();
        Utils.assertBNEq(totalValueInStrategies, 0);
    });

    it.only('Verify: exchange on 1inch', async function () {
        
        const exchangeTester = vault.address;

        // await topUpUsdtByAddress(new BigNumber(10 ** 12), exchangeTester);
        await sendEthers(exchangeTester, new BigNumber(200 * 10 ** 18));
        // const accounts = await ethers.getSigners();
        // accounts[0].sendEthers
        // await accounts[0].sendEthers(exchangeTester,new BigNumber(2 * 10 ** 18));
        // await send.ether(accounts[0].address,exchangeTester,new BigNumber(20 * 10 ** 18));

        await swap(exchangeTester, ETH, USDT,0);
        await swap(exchangeTester, USDT, USDC,0);
        await swap(exchangeTester, USDC, DAI,0);
        await swap(exchangeTester, DAI, GUSD,0);
        await swap(exchangeTester, GUSD, LUSD,0);
        await swap(exchangeTester, LUSD, ETH,0);
        await swap(exchangeTester, ETH, stETH,0);
        await swap(exchangeTester, stETH, rETH,0);
        await swap(exchangeTester, rETH, sETH,0);
        await swap(exchangeTester, sETH, cbETH,0);
        await swap(exchangeTester, cbETH, ETH,0);
        
    });

    it('Vault Verify: exchange on Paraswap', async function () {
        
        const exchangeTester = vault.address;

        // await topUpUsdtByAddress(new BigNumber(10 ** 12), exchangeTester);
        await sendEthers(exchangeTester, new BigNumber(200 * 10 ** 18));

        await swapOnPara(exchangeTester, tokenMap.ETH, tokenMap.USDT,1);
        await swapOnPara(exchangeTester, tokenMap.USDT, tokenMap.USDC,1);
        await swapOnPara(exchangeTester, tokenMap.USDC, tokenMap.DAI,1);
        await swapOnPara(exchangeTester, tokenMap.DAI, tokenMap.GUSD,1);
        await swapOnPara(exchangeTester, tokenMap.GUSD, tokenMap.LUSD,1);
        await swapOnPara(exchangeTester, tokenMap.LUSD, tokenMap.ETH,1);
        await swapOnPara(exchangeTester, tokenMap.ETH, tokenMap.stETH,1);
        await swapOnPara(exchangeTester, tokenMap.stETH, tokenMap.rETH,1);
        await swapOnPara(exchangeTester, tokenMap.rETH, tokenMap.sETH,1);
        await swapOnPara(exchangeTester, tokenMap.sETH, tokenMap.cbETH,1);
        await swapOnPara(exchangeTester, tokenMap.cbETH, tokenMap.ETH,1);
    });

    it('VaultBuffer Verify: exchange on Paraswap', async function () {
        
        const exchangeTester = vaultBuffer.address;

        // await topUpUsdtByAddress(new BigNumber(10 ** 12), exchangeTester);
        await sendEthers(exchangeTester, new BigNumber(200 * 10 ** 18));

        await swapOnPara(exchangeTester, tokenMap.ETH, tokenMap.USDT,1);
        await swapOnPara(exchangeTester, tokenMap.USDT, tokenMap.DAI,1);
        await swapOnPara(exchangeTester, tokenMap.DAI,tokenMap.USDC,1);
        await swapOnPara(exchangeTester, tokenMap.USDC, tokenMap.GUSD,1);
        await swapOnPara(exchangeTester, tokenMap.GUSD, tokenMap.LUSD,1);
        await swapOnPara(exchangeTester, tokenMap.LUSD, tokenMap.ETH,1);
        await swapOnPara(exchangeTester, tokenMap.ETH, tokenMap.stETH,1);
        await swapOnPara(exchangeTester, tokenMap.stETH, tokenMap.rETH,1);
        await swapOnPara(exchangeTester, tokenMap.rETH, tokenMap.sETH,1);
        await swapOnPara(exchangeTester, tokenMap.sETH, tokenMap.cbETH,1);
        await swapOnPara(exchangeTester, tokenMap.cbETH, tokenMap.ETH,1);
    });
});