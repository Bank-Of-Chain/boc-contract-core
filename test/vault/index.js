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
const USDi = hre.artifacts.require("USDi");
const Vault = hre.artifacts.require('Vault');
const VaultBuffer = hre.artifacts.require('VaultBuffer');
const IVault = hre.artifacts.require('IVault');
const IVaultBuffer = hre.artifacts.require('IVaultBuffer');
const IExchangeAdapter = hre.artifacts.require('IExchangeAdapter');
const VaultAdmin = hre.artifacts.require('VaultAdmin');
const Harvester = hre.artifacts.require('Harvester');
const Dripper = hre.artifacts.require('Dripper');
const MockS3CoinStrategy = hre.artifacts.require('MockS3CoinStrategy');


describe("Vault", function () {
    let accounts;
    let governance;
    let farmer1;
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
            keeper = accounts[19].address;
        });
        await tranferBackUsdt(farmer1);
        await topUpUsdtByAddress(depositAmount, farmer1);
        await tranferBackUsdc(farmer1);
        await topUpUsdcByAddress(usdcDepositAmount, farmer1);
        await tranferBackDai(farmer1);
        await topUpDaiByAddress(daiDepositAmount, farmer1);

        console.log('deploy Vault');
        vault = await Vault.new();

        console.log('deploy accessControlProxy');
        const accessControlProxy = await AccessControlProxy.new();
        accessControlProxy.initialize(governance, governance, vault.address, keeper);

        console.log('deploy ChainlinkPriceFeed');
        // 预言机
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
        for (let i = 0; i < adapters.identifiers_.length; i++) {
            exchangePlatformAdapters[adapters.identifiers_[i]] = adapters.exchangeAdapters_[i];
        }

        console.log('deploy USDi');
        usdi = await USDi.new();
        await usdi.initialize('USDi', 'USDi', 18, vault.address, accessControlProxy.address);


        console.log('vault Buffer');
        vaultBuffer = await VaultBuffer.new();
        await vaultBuffer.initialize('Sharei', 'Sharei', vault.address, usdi.address,accessControlProxy.address);

        const dripper = await Dripper.new();
        await dripper.initialize(accessControlProxy.address, vault.address, MFC.USDT_ADDRESS);

        console.log('deploy Treasury');
        // 国库
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
        // 策略
        mockS3CoinStrategy = await MockS3CoinStrategy.new();
        await mockS3CoinStrategy.initialize(vault.address, harvester.address);

        iVault = await IVault.at(vault.address);
        await iVault.setUSDiAddress(usdi.address);
        await iVault.setVaultBufferAddress(vaultBuffer.address);
    });

    it('验证：Vault可正常添加和移除Asset', async function () {
        const preLength = (await iVault.getSupportAssets()).length
        console.log('添加前Asset的个数=', preLength);
        await iVault.addAsset(underlyingAddress, {from: governance});
        const lastLength = (await iVault.getSupportAssets()).length
        console.log('添加后Asset的个数=', lastLength);
        Utils.assertBNGt(lastLength, preLength);
        await iVault.removeAsset(underlyingAddress, {from: governance});
        const removeLastLength = (await iVault.getSupportAssets()).length
        console.log('移除后Asset的个数=', removeLastLength);
        Utils.assertBNGt(lastLength, removeLastLength);
    });

    it('验证：Vault可正常添加移除所有策略', async function () {
        let addToVaultStrategies = new Array();
        addToVaultStrategies.push({
            strategy: mockS3CoinStrategy.address,
            profitLimitRatio: 100,
            lossLimitRatio: 100
        });

        await iVault.addStrategy(addToVaultStrategies, {from: governance});
        let strategyAddresses = await iVault.getStrategies();
        console.log('添加前策略的个数=', strategyAddresses.length);
        await iVault.removeStrategy(strategyAddresses, {from: governance});
        const length = (await iVault.getStrategies()).length;
        console.log('移除后策略的个数=', length);
        Utils.assertBNEq(length, 0);
    });

    it('验证：Vault可正常投资', async function () {
        await iVault.addAsset(MFC.DAI_ADDRESS, {from: governance});
        await iVault.addAsset(MFC.USDC_ADDRESS, {from: governance});
        await iVault.addAsset(underlyingAddress, {from: governance});

        let _assets = new Array();
        _assets.push(underlyingAddress);
        let _amounts = new Array();
        _amounts.push(depositAmount);
        let _minimumUsdiAmount = 0;
        console.log("投资前vault的usdt的balance:", new BigNumber(await underlying.balanceOf(iVault.address)).div(10 ** tokenDecimals).toFixed());
        console.log("投资前vaultBuffer的usdt的balance:", new BigNumber(await underlying.balanceOf(vaultBuffer.address)).div(10 ** tokenDecimals).toFixed());
        console.log("投资前farmer1的usdi的balance:", new BigNumber(await usdi.balanceOf(farmer1)).div(10 ** usdiDecimals).toFixed());
        console.log("投资前farmer1的sharei的balance:", new BigNumber(await vaultBuffer.balanceOf(farmer1)).div(10 ** vaultBufferDecimals).toFixed());
        console.log("投资前farmer1的usdt的balance:", new BigNumber(await underlying.balanceOf(farmer1)).div(10 ** tokenDecimals).toFixed());

        await underlying.approve(iVault.address, 0, {
            from: farmer1
        });
        await underlying.approve(iVault.address, depositAmount, {
            from: farmer1
        });

        await iVault.mint(_assets, _amounts, _minimumUsdiAmount, {from: farmer1});
        const balance = new BigNumber(await vaultBuffer.balanceOf(farmer1)).toFixed();

        console.log("投资后vault的usdt的balance:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("投资后vaultBuffer的usdt的balance:%s", new BigNumber(await underlying.balanceOf(vaultBuffer.address)).toFixed());
        console.log("投资后farmer1的sharei的balance:%s", balance);
        console.log("投资后farmer1的usdt的balance:%s", new BigNumber(await underlying.balanceOf(farmer1)).toFixed());
        console.log("投资后vault缓存池总资金:%s,总价值：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

        Utils.assertBNGt(balance, 0);
    });


    it('验证：Vault可正常投资其他币种', async function () {
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

        console.log("投资前farmer1的usdc的balance:%s", new BigNumber(await usdcToken.balanceOf(farmer1)).toFixed());
        console.log("投资前farmer1的dai的balance:%s", new BigNumber(await daiToken.balanceOf(farmer1)).toFixed());

        await iVault.mint(_assets, _amounts, 0, {from: farmer1});

        console.log("投资后vault池总资金:%s,总价值：%s", new BigNumber(await iVault.totalAssets()).toFixed(), new BigNumber(await iVault.totalValue()).toFixed());
        console.log("投资后vault策略总资金:%s,总价值：%s", new BigNumber(await iVault.totalDebt()).toFixed(), new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        console.log("投资后vault缓存池总资金:%s,总价值：%s", new BigNumber(await iVault.valueOfTrackedTokens()).toFixed(), new BigNumber(await iVault.totalValueInVault()).toFixed());
        console.log("投资后vault缓存池总资金(包含vaultBuffer):%s,总价值(包含vaultBuffer)：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

        // 充一亿
        const amount = new BigNumber(10).pow(14);
        await topUpUsdtByAddress(amount, testAdapter.address);
        await topUpUsdcByAddress(amount, testAdapter.address);
        await topUpDaiByAddress(amount, testAdapter.address);

        await iVault.setTrusteeFeeBps(1000, {from: governance});

        //开启调仓
        await iVault.startAdjustPosition({from: keeper});

        const beforeBalance = new BigNumber(await usdcToken.balanceOf(farmer1)).div(10 ** tokenDecimals).toFixed();

        console.log("开启调仓后vault的usdt的balance:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("开启调仓后vault的usdc的balance:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("开启调仓后vault的dai的balance:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("开启调仓后farmer1的usdi的balance:%s", new BigNumber(await usdi.balanceOf(farmer1)).toFixed());
        console.log("开启调仓后farmer1的usdt的balance:%s", new BigNumber(await underlying.balanceOf(farmer1)).toFixed());
        console.log("开启调仓后farmer1的dai的balance:%s", new BigNumber(await daiToken.balanceOf(farmer1)).toFixed());
        console.log("开启调仓后farmer1的usdc的balance:%s", beforeBalance);
        console.log("开启调仓后vault缓存池总资金(包含vaultBuffer):%s,总价值(包含vaultBuffer)：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

    });

    it('验证：Vault可正常lend', async function () {
        let addToVaultStrategies = new Array();
        addToVaultStrategies.push({
            strategy: mockS3CoinStrategy.address,
            profitLimitRatio: 100,
            lossLimitRatio: 100
        });
        await iVault.addStrategy(addToVaultStrategies, {from: governance});

        const beforeUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        console.log("lend前vault的usdt的balance:%s", beforeUsdt);
        console.log("lend前vault的usdc的balance:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("lend前vault的dai的balance:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("(usdt,usdc,dai)=(%s,%s,%s)", depositAmount.div(5).toFixed(), usdcDepositAmount.div(5).toFixed(), daiDepositAmount.div(5).toFixed());
        let tokens = [MFC.USDT_ADDRESS, MFC.USDC_ADDRESS, MFC.DAI_ADDRESS];
        let amounts = [depositAmount.div(5), usdcDepositAmount.div(5), daiDepositAmount.div(5)];
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

        console.log("lend后vault池总资金:%s,总价值：%s", new BigNumber(await iVault.totalAssets()).toFixed(), new BigNumber(await iVault.totalValue()).toFixed());
        console.log("lend后vault策略总资金:%s,总价值：%s", new BigNumber(await iVault.totalDebt()).toFixed(), new BigNumber(await iVault.totalValueInStrategies()).toFixed());
        console.log("lend后vault缓存池总资金:%s,总价值：%s", new BigNumber(await iVault.valueOfTrackedTokens()).toFixed(), new BigNumber(await iVault.totalValueInVault()).toFixed());

        const afterUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        console.log("lend后vault的usdt的balance:%s", afterUsdt);
        console.log("lend后vault的usdc的balance:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("lend后vault的dai的balance:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        Utils.assertBNGt(beforeUsdt, afterUsdt);

        await iVault.endAdjustPosition({from: keeper});
        console.log("调仓后farmer1的usdi的balance:%s", new BigNumber(await usdi.balanceOf(farmer1)).toFixed());
        console.log("调仓后vault缓存池总资金(包含vaultBuffer):%s,总价值(包含vaultBuffer)：%s", new BigNumber(await iVault.valueOfTrackedTokensIncludeVaultBuffer()).toFixed(), new BigNumber(await iVault.totalAssetsIncludeVaultBuffer()).toFixed());

        const _amount = new BigNumber(await usdi.balanceOf(farmer1)).div(4).multipliedBy(1).toFixed();
        const _toAsset = MFC.USDC_ADDRESS;
        console.log("赎回币种为:USDC");
        console.log("赎回usdi的数量:%s", new BigNumber(_amount).toFixed());
        const resp = await iVault.burn.call(_amount, _toAsset, 0, false, [], {
            from: farmer1
        });

        tokens = resp[0];
        amounts = resp[1];
        exchangeArray = await Promise.all(
            map(tokens, async (tokenItem, index) => {
                const exchangeAmounts = amounts[index].toString();
                if (tokenItem === _toAsset) {
                    return;
                }
                return {
                    fromToken: tokenItem,
                    toToken: _toAsset,
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

        const exchangeArrayNext = filter(exchangeArray, i => !isEmpty(i));
        const beforeBalance = new BigNumber(await usdcToken.balanceOf(farmer1)).toFixed();

        await iVault.burn(_amount, _toAsset, 0, true, exchangeArrayNext, {from: farmer1});

        const afterBalance = new BigNumber(await usdcToken.balanceOf(farmer1)).toFixed();

        console.log("赎回后vault的usdt的balance:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("赎回后vault的usdc的balance:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("赎回后vault的dai的balance:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("赎回后farmer1的usdi的balance:%s", new BigNumber(await usdi.balanceOf(farmer1)).toFixed());
        console.log("赎回后farmer1的usdt的balance:%s", new BigNumber(await underlying.balanceOf(farmer1)).toFixed());
        console.log("赎回后farmer1的dai的balance:%s", new BigNumber(await daiToken.balanceOf(farmer1)).toFixed());
        console.log("赎回后farmer1的usdc的balance:%s", afterBalance);
        Utils.assertBNGt(afterBalance, beforeBalance);
    });

    it('验证：Vault可正常redeem', async function () {
        console.log("redeem前vault的usdt的balance:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("redeem前vault的usdc的balance:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("redeem前vault的dai的balance:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());
        console.log("(amount,totalDebt)=(%s,%s)", new BigNumber(50).multipliedBy(10**daiDecimals).toFixed(),new BigNumber(await iVault.totalDebt()).toFixed());
        const beforUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();
        await iVault.redeem(mockS3CoinStrategy.address, new BigNumber(50).multipliedBy(10**daiDecimals).toFixed());
        const afterUsdt = new BigNumber(await underlying.balanceOf(iVault.address)).toFixed();

        console.log("redeem后vault的usdt的balance:%s", new BigNumber(await underlying.balanceOf(iVault.address)).toFixed());
        console.log("redeem后vault的usdc的balance:%s", new BigNumber(await usdcToken.balanceOf(iVault.address)).toFixed());
        console.log("redeem后vault的dai的balance:%s", new BigNumber(await daiToken.balanceOf(iVault.address)).toFixed());

        console.log("redeem后vault的valueOfTrackedTokens:%s", new BigNumber(await iVault.valueOfTrackedTokens()).toFixed());
        console.log("redeem后vault的totalAssets:%s", new BigNumber(await iVault.totalAssets()).toFixed());
        Utils.assertBNGt(afterUsdt, beforUsdt);
    });
});