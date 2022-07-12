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
 * recharge core method
 */
async function topUpMain(token, tokenHolder, toAddress, amount) {
    const TOKEN = await IEREC20Mint.at(token);
    const tokenName = await TOKEN.name();
    const farmerBalance = await TOKEN.balanceOf(tokenHolder);
    console.log(`[Transfer]Start recharge ${tokenName}，Balance of token holder：%s`, new BigNumber(farmerBalance).toFormat());

    // 如果待充值的金额大于当前账户余额，则直接充值最大的余额
    // const nextAmount = new BigNumber(farmerBalance > amount ? amount : farmerBalance);
    amount = amount.gt ? amount : new BigNumber(amount);
    const nextAmount = amount.gt(farmerBalance) ? new BigNumber(farmerBalance) : amount;
    await TOKEN.transfer(toAddress, nextAmount, {
        from: tokenHolder,
    });
    console.log(`${tokenName} recharge amount：` + nextAmount.toFormat());
    console.log(`${tokenName} recharge completed`);
    return nextAmount;
}

/**
 * The core method of currency recharge, implemented by mint, enables to recharge the maximum amount of currency
 */
async function topUpMainV2(token, toAddress, amount) {
    const TOKEN = await IEREC20Mint.at(token);
    const tokenName = await TOKEN.name();;
    const tokenOwner = await TOKEN.owner();

    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    const accounts = await ethers.getSigners();
    await send.ether(accounts[0].address, tokenOwner, 10 * 10 ** 18);

    const nextAmount = new BigNumber(amount);
    console.log(`[Mint]Start recharge ${tokenName}，recharge amount：%s`, nextAmount.toFormat());
    await impersonates([tokenOwner]);
    await TOKEN.issue(nextAmount, {
        from: tokenOwner
    });
    await TOKEN.transfer(toAddress, nextAmount, {
        from: tokenOwner,
    });
    console.log(`${tokenName} recharge amount：` + nextAmount.toFormat());
    console.log(`${tokenName} recharge completed`);
    return amount;
}

/**
 * Currency recharge core method, implemented by mint, adapted to owner and mint methods, same level as v2
 */
async function topUpMainV2_1(token, toAddress, amount) {
    const TOKEN = await IEREC20Mint.at(token);
    const tokenName = await TOKEN.name();
    const tokenOwner = await TOKEN.owner();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    const accounts = await ethers.getSigners();
    await send.ether(accounts[0].address, tokenOwner, 10 * 10 ** 18);
    const nextAmount = new BigNumber(amount);
    console.log(`[Mint]Start recharge ${tokenName}，recharge amount：%s`, nextAmount.toFormat());
    await impersonates([tokenOwner]);
    await TOKEN.mint(toAddress, nextAmount, {
        from: tokenOwner
    });
    console.log(`${tokenName} recharge amount：` + nextAmount.toFormat());
    console.log(`${tokenName} recharge completed`);
    return amount;
}

/**
 * Currency recharge core method, implemented by mint, adapted to owner and mint methods, same level as v2
 */
async function topUpMainV2_2(token, toAddress, amount) {
    const TOKEN = await IEREC20Mint.at(token);
    const tokenName = await TOKEN.name();
    const tokenOwner = await TOKEN.supplyController();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    const accounts = await ethers.getSigners();
    await send.ether(accounts[0].address, tokenOwner, 10 * 10 ** 18);

    const nextAmount = new BigNumber(amount);
    console.log(`[Mint]Start recharge ${tokenName}，recharge amount：%s`, nextAmount.toFormat());
    await impersonates([tokenOwner]);

    await TOKEN.increaseSupply(nextAmount, {
        from: tokenOwner
    });
    await TOKEN.transfer(toAddress, nextAmount, {
        from: tokenOwner,
    });
    console.log(`${tokenName} recharge amount：` + nextAmount.toFormat());
    console.log(`${tokenName} recharge completed`);
    return amount;
}

/**
 * Currency recharge core method, implemented by mint, adapted to owner and mint methods, same level as v2
 */
 async function topUpMainV2_3(token, toAddress, amount) {
    const TOKEN = await IEREC20Mint.at(token);
    const tokenName = await TOKEN.name();
    const tokenOwner = await TOKEN.minter();
    console.log('tokenOwner=', tokenOwner);
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    const accounts = await ethers.getSigners();
    await send.ether(accounts[0].address, tokenOwner, 10 * 10 ** 18);
    const nextAmount = new BigNumber(amount);
    console.log(`[Mint]Start recharge ${tokenName}，recharge amount：%s`, nextAmount.toFormat());
    await impersonates([tokenOwner]);
    await TOKEN.mint(toAddress, nextAmount, {
        from: tokenOwner
    });
    console.log(`${tokenName} recharge amount：` + nextAmount.toFormat());
    console.log(`${tokenName} recharge completed`);
    return amount;
}

/**
 * Top up a certain amount of USDT for a certain address
 */
async function topUpUsdtByAddress(amount = new BigNumber(10 * 6), to) {
    if (isEmpty(to)) return 0;
    return topUpMainV2(addresses.USDT_ADDRESS, to, amount);
}

/**
 * Top up a certain amount of dai for a certain address
 */
async function topUpDaiByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.DAI_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.DAI_WHALE_ADDRESS]);

    return topUpMain(addresses.DAI_ADDRESS, addresses.DAI_WHALE_ADDRESS, to, amount);
}

/**
 * Top up a certain amount of busd for a certain address
 */
async function topUpBusdByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.BUSD_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.BUSD_WHALE_ADDRESS]);

    return topUpMain(addresses.BUSD_ADDRESS, addresses.BUSD_WHALE_ADDRESS, to, amount);
}

/**
 * Top up a certain amount of usdc for a certain address
 */
async function topUpUsdcByAddress(amount = new BigNumber(10 ** 6), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.USDC_WHALE_ADDRESS, 10 * 10 ** 18);
    await impersonates([addresses.USDC_WHALE_ADDRESS]);

    return topUpMain(addresses.USDC_ADDRESS, addresses.USDC_WHALE_ADDRESS, to, amount);
}

/**
 * Top up a certain amount of ust for a certain address
 */
async function topUpUstByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.UST_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.UST_WHALE_ADDRESS]);
    return topUpMain(addresses.UST_ADDRESS, addresses.UST_WHALE_ADDRESS, to, amount);
}

/**
 * Top up a certain amount of busd for a certain address
 */
async function topUpBusdByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    return topUpMainV2_2(addresses.BUSD_ADDRESS, to, amount);
}

/**
 * Top up a certain amount of mim for a certain address
 */
async function topUpMimByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    return topUpMainV2_1(addresses.MIM_ADDRESS, to, amount);
}
/**
 * Top up a certain amount of tusd for a certain address
 */
async function topUpTusdByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.TUSD_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.TUSD_WHALE_ADDRESS]);
    return topUpMain(addresses.TUSD_ADDRESS, addresses.TUSD_WHALE_ADDRESS, to, amount);
}
/**
 * Top up a certain amount of usdp for a certain address
 */
async function topUpUsdpByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    return topUpMainV2_2(addresses.USDP_ADDRESS, to, amount);
}
/**
 * Top up a certain amount of lusd for a certain address
 */
async function topUpLusdByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.LUSD_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.LUSD_WHALE_ADDRESS]);
    return topUpMain(addresses.LUSD_ADDRESS, addresses.LUSD_WHALE_ADDRESS, to, amount);
}

/**
 * Top up a certain amount of dodo for a certain address
 */
async function topUpDodoCoinByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.DODO_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.DODO_WHALE_ADDRESS]);
    return topUpMain(addresses.DODO_ADDRESS, addresses.DODO_WHALE_ADDRESS, to, amount);
}

/**
 * Top up a certain amount of sushi for a certain address
 */
async function topUpSushiByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.SUSHI_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.SUSHI_WHALE_ADDRESS]);
    return topUpMain(addresses.SUSHI_ADDRESS, addresses.SUSHI_WHALE_ADDRESS, to, amount);
}

/**
 * Top up a certain amount of crv for a certain address
 */
async function topUpCrvByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.CRV_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.DODO_WHALE_ADDRESS]);
    return topUpMain(addresses.CRV_ADDRESS, addresses.CRV_WHALE_ADDRESS, to, amount);
}
/**
 * Top up a certain amount of cvx for a certain address
 */
async function topUpCvxByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.CVX_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.CVX_WHALE_ADDRESS]);
    return topUpMain(addresses.CVX_ADDRESS, addresses.CVX_WHALE_ADDRESS, to, amount);
}

/**
 * Top up a certain amount of bal for a certain address
 */
 async function topUpBalByAddress(amount = new BigNumber(10 ** 18), to) {
    if (isEmpty(to)) return 0;
    const accounts = await ethers.getSigners();
    // Send 10 ETH to the wallet account to make sure the transaction of withdrawing money from it works.
    await send.ether(accounts[0].address, addresses.BAL_WHALE_ADDRESS, 10 ** 18);
    await impersonates([addresses.BAL_WHALE_ADDRESS]);
    return topUpMain(addresses.BAL_ADDRESS, addresses.BAL_WHALE_ADDRESS, to, amount);
}

/**
 * tranfer Back Usdt
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
    console.log(`balance of ${tokenName}  of tokenHolder：` + new BigNumber(await underlying.balanceOf(underlyingWhale)).toFormat());
}
/**
 * tranfer Back Usdc
 * @param {*} address
 */
const tranferBackUsdc = async (address) => {
    const underlying = await IEREC20Mint.at(addresses.USDC_ADDRESS);
    const tokenName = await underlying.name();
    const underlyingWhale = addresses.USDC_WHALE_ADDRESS;
    await impersonates([underlyingWhale]);
    const farmerBalance = await underlying.balanceOf(address);
    await underlying.transfer(underlyingWhale, farmerBalance, {
        from: address,
    });
    console.log(`balance of ${tokenName}  of tokenHolder：` + new BigNumber(await underlying.balanceOf(underlyingWhale)).toFormat());
}
/**
 * tranfer Back dai
 * @param {*} address
 */
const tranferBackDai = async (address) => {
    const underlying = await IEREC20Mint.at(addresses.DAI_ADDRESS);
    const tokenName = await underlying.name();
    const underlyingWhale = addresses.DAI_WHALE_ADDRESS;
    await impersonates([underlyingWhale]);
    const farmerBalance = await underlying.balanceOf(address);
    await underlying.transfer(underlyingWhale, farmerBalance, {
        from: address,
    });
    console.log(`balance of ${tokenName}  of tokenHolder：` + new BigNumber(await underlying.balanceOf(underlyingWhale)).toFormat());
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
    tranferBackUsdc,
    tranferBackDai,
    impersonates,
    topUpMainV2,
    topUpMainV2_1,
    topUpMainV2_2
};