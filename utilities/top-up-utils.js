const addresses = require('./address-config');
const {
    send
} = require('@openzeppelin/test-helpers');
const IEREC20Mint = artifacts.require('IEREC20Mint');
const BigNumber = require('bignumber.js');

const isEmpty = require('lodash/isEmpty');

async function impersonates(targetAccounts) {
    for (i = 0; i < targetAccounts.length; i++) {
        await hre.network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: [targetAccounts[i]],
        });
    }
}

/**
 * 货币充值核心方法
 */
async function topUpMain(token, tokenHolder, toAddress, amount) {
    const TOKEN = await IEREC20Mint.at(token);
    const tokenName = await TOKEN.name();
    const farmerBalance = await TOKEN.balanceOf(tokenHolder);
    console.log(`[Transfer]开始为账户充值 ${tokenName}，拷贝账户余额：%s`, new BigNumber(farmerBalance).toFormat());

    // 如果待充值的金额大于当前账户余额，则直接充值最大的余额
    // const nextAmount = new BigNumber(farmerBalance > amount ? amount : farmerBalance);
    amount = amount.gt ? amount : new BigNumber(amount);
    const nextAmount = amount.gt(farmerBalance) ? new BigNumber(farmerBalance) : amount;
    await TOKEN.transfer(toAddress, nextAmount, {
        from: tokenHolder,
    });
    console.log(`${tokenName} 余额：` + nextAmount.toFormat());
    console.log(`${tokenName} 充值完成`);
    return nextAmount;
}

/**
 * 新的货币充值核心方法，通过mint来实现，能够充值最大数额的货币
 */
async function topUpMainV2(token, toAddress, amount) {
    const TOKEN = await IEREC20Mint.at(token);
    const tokenName = await TOKEN.name();;
    const tokenOwner = await TOKEN.owner();

    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    const accounts = await ethers.getSigners();
    await send.ether(accounts[0].address, tokenOwner, 10 * 10 ** 18);

    const nextAmount = new BigNumber(amount);
    console.log(`[Mint]开始为账户充值 ${tokenName}，充值数量：%s`, nextAmount.toFormat());
    await impersonates([tokenOwner]);
    await TOKEN.issue(nextAmount, {
        from: tokenOwner
    });
    await TOKEN.transfer(toAddress, nextAmount, {
        from: tokenOwner,
    });
    console.log(`${tokenName} 余额：` + nextAmount.toFormat());
    console.log(`${tokenName} 充值完成`);
    return amount;
}

/**
 * 新的货币充值核心方法，通过mint来实现，适配owner和mint方法，与v2同级
 */
async function topUpMainV2_1(token, toAddress, amount) {
    const TOKEN = await IEREC20Mint.at(token);
    const tokenName = await TOKEN.name();
    const tokenOwner = await TOKEN.owner();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    const accounts = await ethers.getSigners();
    await send.ether(accounts[0].address, tokenOwner, 10 * 10 ** 18);
    const nextAmount = new BigNumber(amount);
    console.log(`[Mint]开始为账户充值 ${tokenName}，充值数量：%s`, nextAmount.toFormat());
    await impersonates([tokenOwner]);
    await TOKEN.mint(toAddress, nextAmount, {
        from: tokenOwner
    });
    console.log(`${tokenName} 余额：` + nextAmount.toFormat());
    console.log(`${tokenName} 充值完成`);
    return amount;
}

/**
 * 新的货币充值核心方法，通过mint来实现，适配owner和mint方法，与v2同级
 */
async function topUpMainV2_2(token, toAddress, amount) {
    const TOKEN = await IEREC20Mint.at(token);
    const tokenName = await TOKEN.name();
    const tokenOwner = await TOKEN.supplyController();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    const accounts = await ethers.getSigners();
    await send.ether(accounts[0].address, tokenOwner, 10 * 10 ** 18);

    const nextAmount = new BigNumber(amount);
    console.log(`[Mint]开始为账户充值 ${tokenName}，充值数量：%s`, nextAmount.toFormat());
    await impersonates([tokenOwner]);

    await TOKEN.increaseSupply(nextAmount, {
        from: tokenOwner
    });
    await TOKEN.transfer(toAddress, nextAmount, {
        from: tokenOwner,
    });
    console.log(`${tokenName} 余额：` + nextAmount.toFormat());
    console.log(`${tokenName} 充值完成`);
    return amount;
}

/**
 * 新的货币充值核心方法，通过mint来实现，适配owner和mint方法，与v2同级
 */
 async function topUpMainV2_3(token, toAddress, amount) {
    const TOKEN = await IEREC20Mint.at(token);
    const tokenName = await TOKEN.name();
    const tokenOwner = await TOKEN.minter();
    console.log('tokenOwner=', tokenOwner);
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    const accounts = await ethers.getSigners();
    await send.ether(accounts[0].address, tokenOwner, 10 * 10 ** 18);
    const nextAmount = new BigNumber(amount);
    console.log(`[Mint]开始为账户充值 ${tokenName}，充值数量：%s`, nextAmount.toFormat());
    await impersonates([tokenOwner]);
    await TOKEN.mint(toAddress, nextAmount, {
        from: tokenOwner
    });
    console.log(`${tokenName} 余额：` + nextAmount.toFormat());
    console.log(`${tokenName} 充值完成`);
    return amount;
}

/**
 * 为某个地址充值一定数量的USDT
 */
async function topUpUsdtByAddress(amount = new BigNumber(10 * 6), to) {
    if (isEmpty(to)) return 0;
    return topUpMainV2(addresses.USDT_ADDRESS, to, amount);
}

/**
 * 为某个地址充值一定数量的Dai
 */
async function topUpDaiByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.DAI_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.DAI_WHALE_ADDRESS]);

    return topUpMain(addresses.DAI_ADDRESS, addresses.DAI_WHALE_ADDRESS, to, amount);
}

/**
 * 为某个地址充值一定数量的Busd
 */
async function topUpBusdByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.BUSD_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.BUSD_WHALE_ADDRESS]);

    return topUpMain(addresses.BUSD_ADDRESS, addresses.BUSD_WHALE_ADDRESS, to, amount);
}

/**
 * 为某个地址充值一定数量的usdc
 */
async function topUpUsdcByAddress(amount = new BigNumber(10 ** 6), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.USDC_WHALE_ADDRESS, 10 * 10 ** 18);
    await impersonates([addresses.USDC_WHALE_ADDRESS]);

    return topUpMain(addresses.USDC_ADDRESS, addresses.USDC_WHALE_ADDRESS, to, amount);
}

/**
 * 为某个地址充值一定数量的ust
 */
async function topUpUstByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.UST_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.UST_WHALE_ADDRESS]);
    return topUpMain(addresses.UST_ADDRESS, addresses.UST_WHALE_ADDRESS, to, amount);
}

/**
 * 为某个地址充值一定数量的Busd
 */
async function topUpBusdByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    return topUpMainV2_2(addresses.BUSD_ADDRESS, to, amount);
}

/**
 * 为某个地址充值一定数量的Dai
 */
async function topUpMimByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    return topUpMainV2_1(addresses.MIM_ADDRESS, to, amount);
}
/**
 * 为某个地址充值一定数量的Dai
 */
async function topUpTusdByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.TUSD_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.TUSD_WHALE_ADDRESS]);
    return topUpMain(addresses.TUSD_ADDRESS, addresses.TUSD_WHALE_ADDRESS, to, amount);
}
/**
 * 为某个地址充值一定数量的USDP
 */
async function topUpUsdpByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    return topUpMainV2_2(addresses.USDP_ADDRESS, to, amount);
}
/**
 * 为某个地址充值一定数量的Dai
 */
async function topUpLusdByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.LUSD_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.LUSD_WHALE_ADDRESS]);
    return topUpMain(addresses.LUSD_ADDRESS, addresses.LUSD_WHALE_ADDRESS, to, amount);
}

/**
 * 为某个地址充值一定数量的dodo
 */
async function topUpDodoCoinByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.DODO_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.DODO_WHALE_ADDRESS]);
    return topUpMain(addresses.DODO_ADDRESS, addresses.DODO_WHALE_ADDRESS, to, amount);
}

/**
 * 为某个地址充值一定数量的sushi
 */
async function topUpSushiByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.SUSHI_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.SUSHI_WHALE_ADDRESS]);
    return topUpMain(addresses.SUSHI_ADDRESS, addresses.SUSHI_WHALE_ADDRESS, to, amount);
}

/**
 * 为某个地址充值一定数量的crv
 */
async function topUpCrvByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.CRV_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.DODO_WHALE_ADDRESS]);
    return topUpMain(addresses.CRV_ADDRESS, addresses.CRV_WHALE_ADDRESS, to, amount);
}
/**
 * 为某个地址充值一定数量的CVX
 */
async function topUpCvxByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.CVX_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.CVX_WHALE_ADDRESS]);
    return topUpMain(addresses.CVX_ADDRESS, addresses.CVX_WHALE_ADDRESS, to, amount);
}

/**
 * 为某个地址充值一定数量的BAL
 */
 async function topUpBalByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // 给钱包账户发送1ETH，确保从里面提钱的交易正常。
    await send.ether(accounts[0].address, addresses.BAL_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.BAL_WHALE_ADDRESS]);
    return topUpMain(addresses.BAL_ADDRESS, addresses.BAL_WHALE_ADDRESS, to, amount);
}

/**
 * 将用户的usdt币，转回钱包
 * @param {*} address
 */
const tranferBackUsdt = async (address) => {
    const underlying = await IEREC20Mint.at(addresses.USDT_ADDRESS);
    const tokenName = await underlying.name();
    const underlyingWhale = addresses.USDT_WHALE_ADDRESS;
    await impersonates([underlyingWhale]);
    const farmerBalance = await underlying.balanceOf(address);
    await underlying.transfer(underlyingWhale, farmerBalance, {
        from: address,
    });
    console.log(`${tokenName} 钱包账户余额：` + new BigNumber(await underlying.balanceOf(underlyingWhale)).toFormat());
}

module.exports = {
    topUpMain,
    topUpUsdtByAddress,
    topUpDaiByAddress,
    topUpBusdByAddress,
    topUpUsdcByAddress,
    topUpUstByAddress,
    topUpLusdByAddress,
    topUpTusdByAddress,
    topUpMimByAddress,
    topUpBusdByAddress,
    topUpUsdpByAddress,
    topUpDodoCoinByAddress,
    topUpSushiByAddress,
    topUpCrvByAddress,
    topUpCvxByAddress,
    topUpBalByAddress,
    tranferBackUsdt,
    impersonates,
    topUpMainV2,
    topUpMainV2_1,
    topUpMainV2_2
};