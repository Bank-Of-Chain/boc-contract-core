const chai = require("chai");
const hre = require("hardhat");
const {ethers} = require("hardhat");
const {solidity} = require("ethereum-waffle");
const {utils} = require("ethers");
const MFC = require("../mainnet-fork-test-config");
const {topUpUsdtByAddress, topUpUsdcByAddress, topUpDaiByAddress} = require('../../utilities/top-up-utils');
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
const Harvester = hre.artifacts.require('Harvester');
const MockS3CoinStrategy = hre.artifacts.require('MockS3CoinStrategy');

describe("Vault", function () {
    let accounts;
    let governance;
    let farmer1;
    let keeper;
    let token;
    let tokenDecimals;
    let usdiDecimals;
    let depositAmount
    let daiDepositAmount
    let daiDecimals;
    let usdcDepositAmount
    let usdcDecimals;
    let treasury;
    let testAdapter;
    let mockS3CoinStrategy;
    let harvester;

    // Core protocol contracts
    let usdi;
    let vault;
    let underlying;
    let usdcToken;
    let daiToken;
    let underlyingAddress;
    let valueInterpreter;
    let exchangeAggregator;
    let exchangePlatformAdapters;

    before(async function () {
        usdiDecimals = 18;
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
        await topUpUsdtByAddress(depositAmount, farmer1);
        await topUpUsdcByAddress(usdcDepositAmount, farmer1);
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
        valueInterpreter = await ValueInterpreter.new(chainlinkPriceFeed.address, aggregatedDerivativePriceFeed.address);

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
        await usdi.initialize('USDi', 'USDi', 18, accessControlProxy.address);
        await usdi.setVault(vault.address);

        console.log('deploy Treasury');
        // 国库
        treasury = await Treasury.new();
        await treasury.initialize(accessControlProxy.address, usdi.address);
        await treasury.rebaseOptIn({from: governance});
        await vault.initialize(usdi.address, accessControlProxy.address, treasury.address, exchangeAggregator.address, valueInterpreter.address);

        const harvester = await Harvester.new();
        await harvester.initialize(accessControlProxy.address, vault.address, MFC.USDT_ADDRESS, exchangeAggregator.address);

        console.log("USDT_PRICE:", new BigNumber(await valueInterpreter.price(MFC.USDT_ADDRESS)).toFixed());
        console.log("USDT_CALC:", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.USDT_ADDRESS, 10 ** 6)).toFixed());
        console.log("USDC_PRICE:", new BigNumber(await valueInterpreter.price(MFC.USDC_ADDRESS)).toFixed());
        console.log("USDC_CALC:", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.USDC_ADDRESS, 10 ** 6)).toFixed());
        console.log("DAI_PRICE:", new BigNumber(await valueInterpreter.price(MFC.DAI_ADDRESS)).toFixed());
        console.log("DAI_CALC:", new BigNumber(await valueInterpreter.calcCanonicalAssetValueInUsd(MFC.DAI_ADDRESS, new BigNumber(10 ** 18))).toFixed());
        console.log('mockS3CoinStrategy USDi');
        // 策略
        mockS3CoinStrategy = await MockS3CoinStrategy.new();
        await mockS3CoinStrategy.initialize(vault.address, harvester.address);

    });

    it('验证：Vault可正常添加和移除Asset', async function () {
        const preLength = (await vault.getSupportAssets()).length
        console.log('添加前Asset的个数=', preLength);
        await vault.addAsset(underlyingAddress, {from: governance});
        const lastLength = (await vault.getSupportAssets()).length
        console.log('添加后Asset的个数=', lastLength);
        Utils.assertBNGt(lastLength, preLength);
        await vault.removeAsset(underlyingAddress, {from: governance});
        const removeLastLength = (await vault.getSupportAssets()).length
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

        await vault.addStrategy(addToVaultStrategies, {from: governance});
        let strategyAddresses = await vault.getStrategies();
        console.log('添加前策略的个数=', strategyAddresses.length);
        await vault.removeStrategy(strategyAddresses, {from: governance});
        const length = (await vault.getStrategies()).length;
        console.log('移除后策略的个数=', length);
        Utils.assertBNEq(length, 0);
    });

    it('验证：Vault可正常投资', async function () {
        await vault.addAsset(underlyingAddress, {from: governance});

        let _assets = new Array();
        _assets.push(underlyingAddress);
        let _amounts = new Array();
        _amounts.push(depositAmount);
        let _minimumUsdiAmount = 0;
        console.log("投资前vault的usdt的balance:", new BigNumber(await underlying.balanceOf(vault.address)).div(10 ** tokenDecimals).toFixed());
        console.log("投资前farmer1的usdi的balance:", new BigNumber(await usdi.balanceOf(farmer1)).div(10 ** usdiDecimals).toFixed());
        console.log("投资前farmer1的usdt的balance:", new BigNumber(await underlying.balanceOf(farmer1)).div(10 ** daiDecimals).toFixed());

        await underlying.approve(vault.address, 0, {
            from: farmer1
        });
        await underlying.approve(vault.address, depositAmount, {
            from: farmer1
        });

        await vault.mint(_assets, _amounts, _minimumUsdiAmount, {from: farmer1});
        const balance = new BigNumber(await usdi.balanceOf(farmer1)).div(10 ** usdiDecimals).toFixed();

        console.log("投资后vault的usdt的balance:", new BigNumber(await underlying.balanceOf(vault.address)).div(10 ** tokenDecimals).toFixed());
        console.log("投资后farmer1的usdi的balance:", balance);
        console.log("投资后farmer1的usdt的balance:", new BigNumber(await underlying.balanceOf(farmer1)).div(10 ** tokenDecimals).toFixed());

        Utils.assertBNGt(balance, 0);
    });


    it('验证：Vault可正常赎回', async function () {
        await vault.addAsset(MFC.USDC_ADDRESS, {from: governance});
        await vault.addAsset(MFC.DAI_ADDRESS, {from: governance});

        let _assets = new Array();
        _assets.push(MFC.USDC_ADDRESS);
        _assets.push(MFC.DAI_ADDRESS);
        let _amounts = new Array();
        _amounts.push(usdcDepositAmount);
        _amounts.push(daiDepositAmount);

        await usdcToken.approve(vault.address, 0, {
            from: farmer1
        });
        await usdcToken.approve(vault.address, usdcDepositAmount, {
            from: farmer1
        });

        await daiToken.approve(vault.address, 0, {
            from: farmer1
        });
        await daiToken.approve(vault.address, daiDepositAmount, {
            from: farmer1
        });

        console.log("投资前farmer1的usdc的balance:", new BigNumber(await usdcToken.balanceOf(farmer1)).div(10 ** usdcDecimals).toFixed());
        console.log("投资前farmer1的dai的balance:", new BigNumber(await daiToken.balanceOf(farmer1)).div(10 ** daiDecimals).toFixed());

        await vault.mint(_assets, _amounts, 0, {from: farmer1});

        // 充一亿
        const amount = new BigNumber(10).pow(14);
        await topUpUsdtByAddress(amount, testAdapter.address);
        await topUpUsdcByAddress(amount, testAdapter.address);
        await topUpDaiByAddress(amount, testAdapter.address);

        await vault.setTrusteeFeeBps(1000, {from: governance});

        const beforeBalance = new BigNumber(await usdcToken.balanceOf(farmer1)).div(10 ** tokenDecimals).toFixed();

        console.log("赎回前vault的usdt的balance:", new BigNumber(await underlying.balanceOf(vault.address)).div(10 ** tokenDecimals).toFixed());
        console.log("赎回前vault的usdc的balance:", new BigNumber(await usdcToken.balanceOf(vault.address)).div(10 ** usdcDecimals).toFixed());
        console.log("赎回前vault的dai的balance:", new BigNumber(await daiToken.balanceOf(vault.address)).div(10 ** daiDecimals).toFixed());
        console.log("赎回前farmer1的usdi的balance:", new BigNumber(await usdi.balanceOf(farmer1)).div(10 ** usdiDecimals).toFixed());
        console.log("赎回前farmer1的usdt的balance:", new BigNumber(await underlying.balanceOf(farmer1)).div(10 ** tokenDecimals).toFixed());
        console.log("赎回前farmer1的dai的balance:", new BigNumber(await daiToken.balanceOf(farmer1)).div(10 ** daiDecimals).toFixed());
        console.log("赎回前farmer1的usdc的balance:", beforeBalance);

        const _amount = new BigNumber(await usdi.balanceOf(farmer1)).div(4).multipliedBy(1).toFixed();
        const _toAsset = MFC.USDC_ADDRESS;
        console.log("赎回币种为:USDC");
        console.log("赎回usdi的数量:", new BigNumber(_amount).div(10 ** usdiDecimals).toFixed());
        const resp = await vault.burn.call(_amount, _toAsset, 0, false, [], {
            from: farmer1
        });

        const tokens = resp[0]
        const amounts = resp[1]
        const exchangeArray = await Promise.all(
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

        await vault.burn(_amount, _toAsset, 0, true, exchangeArrayNext, {from: farmer1});

        const afterBalance = new BigNumber(await usdcToken.balanceOf(farmer1)).div(10 ** tokenDecimals).toFixed();

        console.log("赎回后vault的usdt的balance:", new BigNumber(await underlying.balanceOf(vault.address)).div(10 ** tokenDecimals).toFixed());
        console.log("赎回后vault的usdc的balance:", new BigNumber(await usdcToken.balanceOf(vault.address)).div(10 ** usdcDecimals).toFixed());
        console.log("赎回后vault的dai的balance:", new BigNumber(await daiToken.balanceOf(vault.address)).div(10 ** daiDecimals).toFixed());
        console.log("赎回后farmer1的usdi的balance:", new BigNumber(await usdi.balanceOf(farmer1)).div(10 ** usdiDecimals).toFixed());
        console.log("赎回后farmer1的usdt的balance:", new BigNumber(await underlying.balanceOf(farmer1)).div(10 ** tokenDecimals).toFixed());
        console.log("赎回后farmer1的dai的balance:", new BigNumber(await daiToken.balanceOf(farmer1)).div(10 ** daiDecimals).toFixed());
        console.log("赎回后farmer1的usdc的balance:", afterBalance);
        Utils.assertBNGt(afterBalance, beforeBalance);
    });

    it('验证：Vault可正常lend', async function () {
        let addToVaultStrategies = new Array();
        addToVaultStrategies.push({
            strategy: mockS3CoinStrategy.address,
            profitLimitRatio: 100,
            lossLimitRatio: 100
        });
        await vault.addStrategy(addToVaultStrategies, {from: governance});

        const beforUsdt = new BigNumber(await underlying.balanceOf(vault.address)).div(10 ** tokenDecimals).toFixed();
        console.log("lend前vault的usdt的balance:", beforUsdt);
        console.log("lend前vault的usdc的balance:", new BigNumber(await usdcToken.balanceOf(vault.address)).div(10 ** usdcDecimals).toFixed());
        console.log("lend前vault的dai的balance:", new BigNumber(await daiToken.balanceOf(vault.address)).div(10 ** daiDecimals).toFixed());
        console.log("(usdt,usdc,dai)=", depositAmount.div(5).div(10 ** tokenDecimals).toFixed(), usdcDepositAmount.div(5).div(10 ** usdcDecimals).toFixed(), daiDepositAmount.div(5).div(10 ** daiDecimals).toFixed());
        const tokens = [MFC.USDT_ADDRESS, MFC.USDC_ADDRESS, MFC.DAI_ADDRESS];
        const amounts = [depositAmount.div(5), usdcDepositAmount.div(5), daiDepositAmount.div(5)];
        const exchangeArray = await Promise.all(
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

        await vault.lend(mockS3CoinStrategy.address, exchangeArray);

        const afterUsdt = new BigNumber(await underlying.balanceOf(vault.address)).div(10 ** tokenDecimals).toFixed();
        console.log("lend后vault的usdt的balance:", afterUsdt);
        console.log("lend后vault的usdc的balance:", new BigNumber(await usdcToken.balanceOf(vault.address)).div(10 ** usdcDecimals).toFixed());
        console.log("lend后vault的dai的balance:", new BigNumber(await daiToken.balanceOf(vault.address)).div(10 ** daiDecimals).toFixed());
        Utils.assertBNGt(beforUsdt, afterUsdt);
    });

    it('验证：Vault可正常redeem', async function () {

        console.log("redeem前vault的usdt的balance:", new BigNumber(await underlying.balanceOf(vault.address)).div(10 ** tokenDecimals).toFixed());
        console.log("redeem前vault的usdc的balance:", new BigNumber(await usdcToken.balanceOf(vault.address)).div(10 ** usdcDecimals).toFixed());
        console.log("redeem前vault的dai的balance:", new BigNumber(await daiToken.balanceOf(vault.address)).div(10 ** daiDecimals).toFixed());
        console.log("(amount)=", new BigNumber(50).times(10 ** usdiDecimals).toFixed());
        const beforUsdt = new BigNumber(await underlying.balanceOf(vault.address)).div(10 ** tokenDecimals).toFixed();
        await vault.redeem(mockS3CoinStrategy.address, new BigNumber(50).times(10 ** usdiDecimals));
        const afterUsdt = new BigNumber(await underlying.balanceOf(vault.address)).div(10 ** tokenDecimals).toFixed();

        console.log("redeem后vault的usdt的balance:", new BigNumber(await underlying.balanceOf(vault.address)).div(10 ** tokenDecimals).toFixed());
        console.log("redeem后vault的usdc的balance:", new BigNumber(await usdcToken.balanceOf(vault.address)).div(10 ** usdcDecimals).toFixed());
        console.log("redeem后vault的dai的balance:", new BigNumber(await daiToken.balanceOf(vault.address)).div(10 ** daiDecimals).toFixed());

        console.log("redeem后vault的valueOfTrackedTokens:", new BigNumber(await vault.valueOfTrackedTokens()).div(10 ** usdiDecimals).toFixed());
        console.log("redeem后vault的totalAssets:", new BigNumber(await vault.totalAssets()).div(10 ** usdiDecimals).toFixed());
        Utils.assertBNGt(afterUsdt, beforUsdt);
    });
});