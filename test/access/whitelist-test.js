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
const Whitelist = hre.artifacts.require('Whitelist');
const IWhitelist = hre.artifacts.require('IWhitelist');

describe("Whitelist", function () {
    let accounts;
    let governance;
    let vaultManager;
    let farmer;
    let keeper;
    let whitelist;

    before(async function () {
        await ethers.getSigners().then((resp) => {
            accounts = resp;
            governance = accounts[0].address;
            vaultManager = accounts[1].address;
            farmer = accounts[2].address;
            keeper = accounts[19].address;
        });

        console.log('deploy accessControlProxy');
        const accessControlProxy = await AccessControlProxy.new();
        accessControlProxy.initialize(governance, governance, vaultManager, keeper);

        console.log('deploy Whitelist');
        whitelist = await Whitelist.new();
        await whitelist.initialize(accessControlProxy.address);
        console.log("Whitelist address = ",whitelist.address)

    });

    it('Verify: Whitelist lenth is eq 0', async function () {
        const whitelists = await whitelist.getWhitelists({from: farmer});
        const whitelistsLength = whitelists.length;
        console.log("whitelistsLength=",whitelistsLength);
        Utils.assertBNEq(whitelistsLength, 0);
    });

    it('Verify: Whitelist can batch add and remove', async function () {
        await whitelist.addAddressesToWhitelist([keeper,farmer], {from: vaultManager});
        let whitelists = await whitelist.getWhitelists({from: farmer});
        let whitelistsLength = whitelists.length;
        console.log("after added whitelistsLength=",whitelistsLength);
        Utils.assertBNGt(whitelistsLength, 0);
        console.log("after added isWhitelisted(keeper)=",(await whitelist.isWhitelisted(keeper, {from: keeper})).toString());
        console.log("after added isWhitelisted(farmer)=",(await whitelist.isWhitelisted(farmer, {from: farmer})).toString());

        await whitelist.removeAddressesFromWhitelist([keeper,farmer], {from: vaultManager});
        console.log("after removed isWhitelisted(keeper)=",(await whitelist.isWhitelisted(keeper, {from: keeper})).toString());
        console.log("after removed isWhitelisted(keeper)=",(await whitelist.isWhitelisted(farmer, {from: farmer})).toString());
        whitelists = await whitelist.getWhitelists({from: farmer});
        whitelistsLength = whitelists.length;
        console.log("after removed whitelistsLength=",whitelistsLength);
        Utils.assertBNEq(whitelistsLength, 0);

        await whitelist.addAddressesToWhitelist([keeper,farmer], {from: vaultManager});
        whitelists = await whitelist.getWhitelists({from: farmer});
        whitelistsLength = whitelists.length;
        console.log("after added whitelistsLength=",whitelistsLength);
        Utils.assertBNGt(whitelistsLength, 0);
        console.log("after added isWhitelisted(keeper)=",(await whitelist.isWhitelisted(keeper, {from: keeper})).toString());
        console.log("after added isWhitelisted(farmer)=",(await whitelist.isWhitelisted(farmer, {from: farmer})).toString());

        await whitelist.removeAddressesFromWhitelist([keeper], {from: vaultManager});
        console.log("after removed isWhitelisted(keeper)=",(await whitelist.isWhitelisted(keeper, {from: keeper})).toString());
        console.log("after removed isWhitelisted(keeper)=",(await whitelist.isWhitelisted(farmer, {from: farmer})).toString());
        whitelists = await whitelist.getWhitelists({from: farmer});
        whitelistsLength = whitelists.length;
        console.log("after removed whitelistsLength=",whitelistsLength);
        Utils.assertBNEq(whitelistsLength, 1);
    });

    it('Verify: Whitelist can check permission', async function () {
        await expect(
            whitelist.addAddressesToWhitelist([keeper,farmer], {from: keeper})
        ).to.be.revertedWith("vault manager");
        await expect(
            whitelist.removeAddressesFromWhitelist([keeper,farmer], {from: keeper})
        ).to.be.revertedWith("vault manager");
    });

});