const address = require('../utilities/address-config');
const {
    getChainlinkConfig
} = require('./../utilities/chainlink-config');
const mapValues = require('lodash/mapValues');

const config = getChainlinkConfig();
const dateTime = 24 * 60 * 60 * 60;
// test environment, set the expiration time of the oracle to 1 day to prevent expiration.
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