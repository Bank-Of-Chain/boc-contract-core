const address = require('../utilities/address-config');
const {
    getChainlinkConfig
} = require('./../utilities/chainlink-config');
const mapValues = require('lodash/mapValues');

const config = getChainlinkConfig();
const dateTime = 24 * 60 * 60 * 60;
// 测试环境，将预言机的过期时间设置成1天，防止过期。
const nextConfig = {
    ...config,
    ETH_USD_HEARTBEAT: dateTime,
    aggregators: mapValues(config.aggregators, item => {
        return {
            ...item,
            heartbeat: dateTime
        }
    })
}
module.exports = {
    ...address,
    CHAINLINK: nextConfig
};