const Utils = require("./assert-utils.js");
const {
    logPercent
} = require('./log-utils')
/**
 * 模拟区块增长
 * @param {number} days 天数
 */
async function advanceBlock(days) {
    for (const i of Array.from(new Array(days)).map((i, index) => index + 1)) {
        console.log("day: ", i);
        for (const hour of Array.from(new Array(24)).map((i, index) => index + 1)) {
            logPercent(hour * 100 / 24);
            let blocksPerHour = 211;
            await Utils.advanceNBlock(blocksPerHour);
        }
    }
}

async function advanceBlockOfHours(hours) {
    for (const hour of Array.from(new Array(hours)).map((i, index) => index + 1)) {
        console.log("hours: ", hour);
        logPercent(hour * 100 / hours);
        let blocksPerHour = 211;
        await Utils.advanceNBlock(blocksPerHour);
    }
}

async function closestBlockAfterTimestamp(timestamp) {
    let height = await ethers.provider.getBlockNumber();
    let lo = 0;
    let hi = height;
    while (hi - lo > 1) {
        let mid = lo + Math.floor((hi - lo) / 2);
        if ((await getBlock(mid)).timestamp > timestamp) {
            hi = mid;
        } else {
            lo = mid;
        }
    }
    if (hi != height) {
        return hi;
    } else {
        return 0;
    }
}

function getDaysAgoTimestamp(blockTimestamp, daysAgo) {
    //let nowMs = new Date(new Date().toLocaleDateString()).getTime()/1000;
    return blockTimestamp - 60 * 60 * 24 * daysAgo;
}

async function getLatestBlock() {
    const height = await ethers.provider.getBlockNumber();
    return (await ethers.provider.getBlock(height));
}

async function getBlock(height) {
    return await ethers.provider.getBlock(height);
}

module.exports = {
    advanceBlock,
    advanceBlockOfHours,
    closestBlockAfterTimestamp,
    getDaysAgoTimestamp,
    getLatestBlock,
    getBlock,
}