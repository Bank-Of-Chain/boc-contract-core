const chai = require("chai");
const hre = require("hardhat");
const {ethers} = require("hardhat");
const {solidity} = require("ethereum-waffle");
const {utils} = require("ethers");
const MFC = require("../mainnet-fork-test-config");
const {topUpUsdtByAddress, topUpUsdcByAddress, topUpDaiByAddress,tranferBackUsdt,
    tranferBackUsdc,
    tranferBackDai} = require('../../utilities/top-up-utils');
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
const Dripper = hre.artifacts.require('Dripper');
const PegToken = hre.artifacts.require('PegToken');
const MockS3CoinStrategy = hre.artifacts.require('MockS3CoinStrategy');


describe("Vault", function () {
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

        console.log('deploy Vault');
        vault = await Vault.new();

        console.log('deploy accessControlProxy');
        const accessControlProxy = await AccessControlProxy.new();
        accessControlProxy.initialize(governance, governance, vault.address, keeper);

        console.log('deploy ChainlinkPriceFeed');
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

        console.log('deploy AggregatedDerivativePriceFeed');
        let derivatives = new Array();
        const priceFeeds = new Array();
        const aggregatedDerivativePriceFeed = await AggregatedDerivativePriceFeed.new(derivatives, priceFeeds, accessControlProxy.address);


        console.log('deploy ValueInterpreter');
        valueInterpreter = await ValueInterpreter.new(chainlinkPriceFeed.address, aggregatedDerivativePriceFeed.address, accessControlProxy.address);

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

        const dripper = await Dripper.new();
        await dripper.initialize(accessControlProxy.address, vault.address, MFC.USDT_ADDRESS);

        console.log('deploy Treasury');
        // treasury
        treasury = await Treasury.new();
        await treasury.initialize(accessControlProxy.address);

        await vault.initialize(accessControlProxy.address, treasury.address, exchangeAggregator.address, valueInterpreter.address);
        vaultAdmin = await VaultAdmin.new();
        await vault.setAdminImpl(vaultAdmin.address, {from: governance});

        const harvester = await Harvester.new();
        await harvester.initialize(accessControlProxy.address, dripper.address, MFC.USDT_ADDRESS, vault.address);

        console.log("USDT_PRICE:", new BigNumber(await valueInterpreter.price(MFC.USDT_ADDRESS)).toFixed());
        console.log("USDT_CALC:", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.USDT_ADDRESS, 10 ** 6)).toFixed());
        console.log("USDC_PRICE:", new BigNumber(await valueInterpreter.price(MFC.USDC_ADDRESS)).toFixed());
        console.log("USDC_CALC:", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.USDC_ADDRESS, 10 ** 6)).toFixed());
        console.log("DAI_PRICE:", new BigNumber(await valueInterpreter.price(MFC.DAI_ADDRESS)).toFixed());
        console.log("DAI_CALC:", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.DAI_ADDRESS, new BigNumber(10 ** 18))).toFixed());
        console.log("DAI_CALC(2):", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.DAI_ADDRESS, new BigNumber(2))).toFixed());
        console.log('mockS3CoinStrategy USDi');
        // Strategy
        mockS3CoinStrategy = await MockS3CoinStrategy.new();
        await mockS3CoinStrategy.initialize(vault.address, harvester.address);

        iVault = await IVault.at(vault.address);
        // await iVault.setUSDiAddress(usdi.address);
        await iVault.setVaultBufferAddress(vaultBuffer.address);
        await iVault.setPegTokenAddress(pegToken.address);
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
            strategy: mockS3CoinStrategy.address,
            profitLimitRatio: 100,
            lossLimitRatio: 100
        });

        await iVault.addStrategy(addToVaultStrategies, {from: governance});
        let strategyAddresses = await iVault.getStrategies();
        console.log('Number of policies before adding=', strategyAddresses.length);
        await iVault.removeStrategy(strategyAddresses, {from: governance});
        const length = (await iVault.getStrategies()).length;
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
            strategy: mockS3CoinStrategy.address,
            profitLimitRatio: 100,
            lossLimitRatio: 100
        });
        withdrawQueque.push(mockS3CoinStrategy.address);
        await iVault.addStrategy(addToVaultStrategies, {from: governance});
        await iVault.setWithdrawalQueue(withdrawQueque, {from: governance});

        const beforeUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        console.log("Balance of usdt of vault before lend:%s", beforeUsdt);
        console.log("Balance of usdc of vault before lend:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault before lend:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("(usdt,usdc,dai)=(%s,%s,%s)", depositAmount.toFixed(), usdcDepositAmount.toFixed(), daiDepositAmount.toFixed());
        let tokens = [MFC.USDT_ADDRESS, MFC.USDC_ADDRESS, MFC.DAI_ADDRESS];
        let amounts = [depositAmount.toFixed(), usdcDepositAmount.toFixed(), daiDepositAmount.toFixed()];
        let exchangeArray = await Promise.all(
            map(tokens, async (tokenItem, index) => {
                const exchangeAmounts = amounts[index].toString();
                return {
                    fromToken: tokenItem,
                    toToken: tokenItem,
                    fromAmount: exchangeAmounts,
                    exchangeParam: {
                        platform: exchangePlatformAdapters.testAdapter,
                        method: 0,
                        encodeExchangeArgs: '0x',
                        slippage: 0,
                        oracleAdditionalSlippage: 0
                    }
                }
            })
        );

        await iVault.lend(mockS3CoinStrategy.address, exchangeArray);

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

        await iVault.burn(_amount, 0, {from: farmer1});

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
        await usdcIEREC20Mint.transfer(mockS3CoinStrategy.address, new BigNumber(await usdcToken.balanceOf(farmer1)).div(1000).toFixed(), {
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

        //startAdjustPosition
        console.log("startAdjustPosition");
        let tx =  await iVault.startAdjustPosition({from: keeper});
        let gasUsed = tx.receipt.gasUsed;
        console.log('startAdjustPosition gasUsed: %d', gasUsed);
        console.log("Balance of usdt of vault before redeem:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("Balance of usdc of vault before redeem:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault before redeem:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("(amount,totalDebt)=(%s,%s)", new BigNumber(await iVault.totalDebt()).div(5).toFixed(),new BigNumber(await iVault.totalDebt()).toFixed());
        let beforeUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        console.log("redeem amount: %s",new BigNumber(await iVault.totalDebt()).div(5).toFixed())
        tx =  await iVault.redeem(mockS3CoinStrategy.address, new BigNumber(await iVault.totalDebt()).div(5).toFixed(), 0);
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
        let exchangeArray = await Promise.all(
            map(tokens, async (tokenItem, index) => {
                const exchangeAmounts = amounts[index].toString();
                return {
                    fromToken: tokenItem,
                    toToken: tokenItem,
                    fromAmount: exchangeAmounts,
                    exchangeParam: {
                        platform: exchangePlatformAdapters.testAdapter,
                        method: 0,
                        encodeExchangeArgs: '0x',
                        slippage: 0,
                        oracleAdditionalSlippage: 0
                    }
                }
            })
        );

        await iVault.lend(mockS3CoinStrategy.address, exchangeArray);

        console.log("totalAssets after lend:%s,totalValue：%s", new BigNumber(await iVault.totalAssets()).toFixed(), new BigNumber(await iVault.totalValue()).toFixed());
        console.log("totalDebt after lend:%s,totalValueInStrategies：%s", new BigNumber(await iVault.totalDebt()).toFixed(), new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        console.log("valueOfTrackedTokens after lend:%s,totalValueInVault：%s", new BigNumber(await iVault.valueOfTrackedTokens()).toFixed(), new BigNumber(await iVault.totalValueInVault()).toFixed());

        afterUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        console.log("Balance of usdt of vault after lend:%s", afterUsdt);
        console.log("Balance of usdc of vault after lend:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("Balance of dai of vault after lend:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        Utils.assertBNGt(beforeUsdt, afterUsdt);

        tx = await iVault.endAdjustPosition({from: keeper});
        gasUsed = tx.receipt.gasUsed;
        console.log('endAdjustPosition gasUsed: %d', gasUsed);

        console.log('start distributeWhenDistributing');
        await vaultBuffer.distributeWhenDistributing({from: keeper});
        console.log('end distributeWhenDistributing');

        console.log("Balance of usdi of farmer1 after end adjust position:%s", new BigNumber(await pegToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of usdi of farmer2 after end adjust position:%s", new BigNumber(await pegToken.balanceOf(farmer2)).toFixed());
        console.log("valueOfTrackedTokensIncludeVaultBuffer after end adjust position:%s,totalAssetsIncludeVaultBuffer：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());
    });

    it('Verify：burn from strategy', async function (){
        await iVault.rebase();
        console.log("totalValueInStrategies before withdraw: %s",new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        console.log("totalAssets before withdraw: %s",new BigNumber(await iVault.totalAssets()).toFixed());
        console.log("Balance of usdi of farmer1 before withdraw: %s", new BigNumber(await pegToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of usdi of farmer2 before withdraw: %s", new BigNumber(await pegToken.balanceOf(farmer2)).toFixed());
        let _amount =  new BigNumber(await pegToken.balanceOf(farmer1)).toFixed();
        await iVault.burn(_amount, 0, {from: farmer1});
        console.log("totalValueInStrategies after farmer1 withdraw: %s",new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        _amount =  new BigNumber(await pegToken.balanceOf(farmer2)).minus(new BigNumber(10).pow(18)).toFixed();
        await iVault.burn(_amount, 0, {from: farmer2});
        const totalValueInStrategies = new BigNumber(await iVault.totalValueInStrategies()).toFixed();
        console.log("totalValueInStrategies after withdraw: %s",totalValueInStrategies);
        console.log("totalAssets after withdraw: %s",new BigNumber(await iVault.totalAssets()).toFixed());
        console.log("Balance of usdi of farmer1 after withdraw: %s", new BigNumber(await pegToken.balanceOf(farmer1)).toFixed());
        console.log("Balance of usdi of farmer2 after withdraw: %s", new BigNumber(await pegToken.balanceOf(farmer2)).toFixed());

        Utils.assertBNEq(totalValueInStrategies, 0);
    });

    // it('Verify：multicall', async function (){
    //     await iVault.multicall([
    //         iVault.contract.methods.setMaxTimestampBetweenTwoReported(1000).encodeABI(),
    //         iVault.contract.methods.setRedeemFeeBps(1000).encodeABI(),
    //         iVault.contract.methods.setMinimumInvestmentAmount(10000000000000).encodeABI()
    //     ],{from:governance});
    //     console.log(new BigNumber(await iVault.maxTimestampBetweenTwoReported()).toFixed());
    //     console.log(new BigNumber(await iVault.minimumInvestmentAmount()).toFixed());
    //     Utils.assertBNEq(new BigNumber(await iVault.maxTimestampBetweenTwoReported()).toFixed(), 1000);
    // });
});