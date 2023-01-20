const MFC = require("../mainnet-fork-test-config");
const { ethers } = require('hardhat');
const {topUpUsdtByAddress, topUpUsdcByAddress, topUpDaiByAddress
} = require('../../utilities/top-up-utils');
const Utils = require('../../utilities/assert-utils');
const {send, balance, expectEvent, expectRevert, BN} = require("@openzeppelin/test-helpers");
const {BigNumber} = ethers;

const ERC20 = hre.artifacts.require('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');
const AccessControlProxy = artifacts.require('AccessControlProxy');
const ValueInterpreter = hre.artifacts.require("ValueInterpreter");
const ChainlinkPriceFeed = hre.artifacts.require("ChainlinkPriceFeed");
const AggregatedDerivativePriceFeed = hre.artifacts.require("AggregatedDerivativePriceFeed");
const ExchangeAggregator = artifacts.require('ExchangeAggregator')
const TestAdapter = artifacts.require('TestAdapter')

const NativeToken = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

async function convert2TokenAmount(tokenAddr, amount) {
    let decimals = 0;
    if (tokenAddr == NativeToken) {
        decimals = BigNumber.from(10).pow(18);
    } else {
        const token = await ERC20.at(tokenAddr);
        decimals = BigNumber.from(10).pow((await token.decimals()).toString());
    }
    return (decimals.mul(BigNumber.from(BigInt(amount)))).toString();
}

async function balanceOfToken(account, tokenAddr) {
    if (tokenAddr == NativeToken) {
        return BigNumber.from(BigInt(await ethers.provider.getBalance(account)));
    }
    const token = await ERC20.at(tokenAddr);
    return BigNumber.from((await token.balanceOf(account)).toString());
}

describe('ExchangeAggregator test.', function () {
    let governance;
    let keeper;
    let vault;
    let farmer1;
    let exchangeAggregator;
    let amount = BigNumber.from(10000);
    let testAdapter;

    before('INIT', async function () {
        await ethers.getSigners().then((resp) => {
            accounts = resp;
            governance = accounts[0].address;
            farmer1 = accounts[13].address;
            vault = accounts[2].address;
            keeper = accounts[19].address;
        });

        const accessControlProxy = await AccessControlProxy.new();
        accessControlProxy.initialize(governance, governance, vault, keeper);
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
        exchangeAggregator = await ExchangeAggregator.new([testAdapter.address], accessControlProxy.address);
        await topUpUsdtByAddress(await convert2TokenAmount(MFC.USDT_ADDRESS, amount), farmer1);
        await topUpUsdcByAddress(await convert2TokenAmount(MFC.USDC_ADDRESS, amount.mul(20)), testAdapter.address);
        await topUpDaiByAddress(await convert2TokenAmount(MFC.DAI_ADDRESS, amount.mul(20)), testAdapter.address);

        await send.ether(governance, testAdapter.address, 10 * 10 ** 18)
    });

    it('verify：ExchangeAggregator removeExchangeAdapters', async function () {
        const beforeLength = (await exchangeAggregator.getExchangeAdapters())?._identifiers?.length??0;
        console.log("beforeLength=",beforeLength);
        await exchangeAggregator.removeExchangeAdapters([testAdapter.address]);
        const afterLength = (await exchangeAggregator.getExchangeAdapters())?._identifiers?.length??0;
        console.log("afterLength=",afterLength);
        Utils.assertBNGt(beforeLength, afterLength);
    });

    it('verify：ExchangeAggregator addExchangeAdapters', async function () {
        const beforeLength = (await exchangeAggregator.getExchangeAdapters())?._identifiers?.length??0;
        console.log("beforeLength=",beforeLength);
        await exchangeAggregator.addExchangeAdapters([testAdapter.address]);
        const afterLength = (await exchangeAggregator.getExchangeAdapters())?._identifiers?.length??0;
        console.log("afterLength=",afterLength);
        Utils.assertBNGt(afterLength, beforeLength);
    });

    it('verify：ExchangeAggregator swap(USDT=>USDC)', async function () {
        const exchangeParam = {
            platform: testAdapter.address,
            method: 0,
            encodeExchangeArgs: "0x",
            slippage: 0,
            oracleAdditionalSlippage: 0,
        };

        const swapDesc = {
            amount: BigNumber.from((await balanceOfToken(farmer1, MFC.USDT_ADDRESS)).toString()).div(2),
            srcToken: MFC.USDT_ADDRESS,
            dstToken: MFC.USDC_ADDRESS,
            receiver: farmer1
        };
        const beforeUSDC = (await balanceOfToken(farmer1, swapDesc.dstToken)).toString();
        console.log("beforeUSDC = ", beforeUSDC);

        const token = await ERC20.at(swapDesc.srcToken);
        await token.approve(exchangeAggregator.address, swapDesc.amount, { from: farmer1 });

        await exchangeAggregator.swap(exchangeParam.platform, exchangeParam.method, exchangeParam.encodeExchangeArgs, swapDesc, { from: farmer1});
        const afterUSDC = (await balanceOfToken(farmer1, swapDesc.dstToken)).toString();
        console.log("afterUSDC = ", afterUSDC);
        Utils.assertBNGt(afterUSDC, beforeUSDC);
    });

    it('verify：ExchangeAggregator batchSwap(USDT,USDC=>DAI)', async function () {
        let swapParams = [];
        swapParams.push({
            platform: testAdapter.address,
            method: 0,
            data: "0x",
            swapDescription:{
                amount: (await balanceOfToken(farmer1, MFC.USDT_ADDRESS)).toString(),
                srcToken: MFC.USDT_ADDRESS,
                dstToken: MFC.DAI_ADDRESS,
                receiver: farmer1
            }
        });
        swapParams.push({
            platform: testAdapter.address,
            method: 0,
            data: "0x",
            swapDescription:{
                amount: (await balanceOfToken(farmer1, MFC.USDC_ADDRESS)).toString(),
                srcToken: MFC.USDC_ADDRESS,
                dstToken: MFC.DAI_ADDRESS,
                receiver: farmer1
            }
        });
        const beforeDAI = (await balanceOfToken(farmer1 ,MFC.DAI_ADDRESS)).toString();
        for(let i=0;i<swapParams.length;i++){
            const swapDesc = swapParams[i].swapDescription;
            const token = await ERC20.at(swapDesc.srcToken);
            await token.approve(exchangeAggregator.address, swapDesc.amount, { from: farmer1 });
        }

        console.log("beforeDAI = ", beforeDAI);
        await exchangeAggregator.batchSwap(swapParams, { from: farmer1});
        const afterDAI = (await balanceOfToken(farmer1, MFC.DAI_ADDRESS)).toString();
        console.log("afterDAI = ", afterDAI);
        Utils.assertBNGt(afterDAI, beforeDAI);
    });

    it('verify：ExchangeAggregator swap(DAI=>ETH)', async function () {
        const exchangeParam = {
            platform: testAdapter.address,
            method: 0,
            encodeExchangeArgs: "0x",
            slippage: 0,
            oracleAdditionalSlippage: 0,
        };

        const swapDesc = {
            amount: BigNumber.from(BigInt((await balanceOfToken(farmer1, MFC.DAI_ADDRESS)).div(2).toString())),
            srcToken: MFC.DAI_ADDRESS,
            dstToken: NativeToken,
            receiver: farmer1
        };
        const beforeETH = (await balanceOfToken(farmer1, swapDesc.dstToken)).toString();
        console.log("beforeETH = ", beforeETH);
        const token = await ERC20.at(swapDesc.srcToken);
        await token.approve(exchangeAggregator.address, swapDesc.amount, { from: farmer1 });
        await exchangeAggregator.swap(exchangeParam.platform, exchangeParam.method, exchangeParam.encodeExchangeArgs, swapDesc, { from: farmer1});
        const afterETH = (await balanceOfToken(farmer1, swapDesc.dstToken)).toString();
        console.log("afterETH = ", afterETH);
        Utils.assertBNGt(afterETH, beforeETH);
    });

    it('verify：ExchangeAggregator swap(ETH=>USDC)', async function () {
        const exchangeParam = {
            platform: testAdapter.address,
            method: 0,
            encodeExchangeArgs: "0x",
            slippage: 0,
            oracleAdditionalSlippage: 0,
        };

        const swapDesc = {
            amount: BigNumber.from(BigInt(10**18)),
            srcToken: NativeToken,
            dstToken: MFC.USDC_ADDRESS,
            receiver: farmer1
        };
        const beforeUSDC = (await balanceOfToken(farmer1, swapDesc.dstToken)).toString();
        console.log("beforeUSDC = ", beforeUSDC);
        await exchangeAggregator.swap(exchangeParam.platform, exchangeParam.method, exchangeParam.encodeExchangeArgs, swapDesc, { from: farmer1,value: swapDesc.amount});
        const afterUSDC = (await balanceOfToken(farmer1, swapDesc.dstToken)).toString();
        console.log("afterUSDC = ", afterUSDC);
        Utils.assertBNGt(afterUSDC, beforeUSDC);
    });

    it('verify：ExchangeAggregator batchSwap(USDC,DAI=>ETH)', async function () {
        let swapParams = [];
        swapParams.push({
            platform: testAdapter.address,
            method: 0,
            data: "0x",
            swapDescription:{
                amount: (await balanceOfToken(farmer1, MFC.USDC_ADDRESS)).toString(),
                srcToken: MFC.USDC_ADDRESS,
                dstToken: NativeToken,
                receiver: farmer1
            }
        });
        swapParams.push({
            platform: testAdapter.address,
            method: 0,
            data: "0x",
            swapDescription:{
                amount: (await balanceOfToken(farmer1, MFC.DAI_ADDRESS)).toString(),
                srcToken: MFC.DAI_ADDRESS,
                dstToken: NativeToken,
                receiver: farmer1
            }
        });
        const beforeETH = (await balanceOfToken(farmer1 ,swapParams[0].swapDescription.dstToken)).toString();
        for(let i=0;i<swapParams.length;i++){
            const swapDesc = swapParams[i].swapDescription;
            const token = await ERC20.at(swapDesc.srcToken);
            await token.approve(exchangeAggregator.address, swapDesc.amount, { from: farmer1 });
        }

        console.log("beforeETH = ", beforeETH);
        await exchangeAggregator.batchSwap(swapParams, { from: farmer1});
        const afterETH = (await balanceOfToken(farmer1, swapParams[0].swapDescription.dstToken)).toString();
        console.log("afterETH = ", afterETH);
        Utils.assertBNGt(afterETH, beforeETH);
    });

    it('verify：ExchangeAggregator batchSwap(ETH=>USDC,DAI)', async function () {
        let swapParams = [];
        swapParams.push({
            platform: testAdapter.address,
            method: 0,
            data: "0x",
            swapDescription:{
                amount: BigNumber.from(BigInt((await balanceOfToken(testAdapter.address, NativeToken)).toString())).sub(2).div(2),
                srcToken: NativeToken,
                dstToken: MFC.USDC_ADDRESS,
                receiver: farmer1
            }
        });
        swapParams.push({
            platform: testAdapter.address,
            method: 0,
            data: "0x",
            swapDescription:{
                amount: BigNumber.from(BigInt((await balanceOfToken(testAdapter.address, NativeToken)).toString())).sub(2).div(2),
                srcToken: NativeToken,
                dstToken: MFC.DAI_ADDRESS,
                receiver: farmer1
            }
        });
        const beforeUSDC = (await balanceOfToken(farmer1 ,swapParams[0].swapDescription.dstToken)).toString();
        let ethAmount = BigNumber.from(0);
        for(let i=0;i<swapParams.length;i++){
            const swapDesc = swapParams[i].swapDescription;
            ethAmount = ethAmount.add(swapDesc.amount);
            console.log("ethAmount,swapDesc.amount=",ethAmount,swapDesc.amount);
        }

        console.log("beforeUSDC = ", beforeUSDC);
        await exchangeAggregator.batchSwap(swapParams, { from: farmer1, value: ethAmount.toString()});
        const afterUSDC = (await balanceOfToken(farmer1, swapParams[0].swapDescription.dstToken)).toString();
        console.log("afterUSDC = ", afterUSDC);
        Utils.assertBNGt(afterUSDC, beforeUSDC);
    });
});