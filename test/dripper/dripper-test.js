const { expect } = require("chai");
const { ethers } = require("hardhat");
const ERC20 = hre.artifacts.require('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');
const MFC = require("../mainnet-fork-test-config");
const {topUpUsdtByAddress} = require('../../utilities/top-up-utils');
const { parseUnits } = require("ethers").utils;
// const Vault = hre.artifacts.require('Vault');
const Treasury = hre.artifacts.require('Treasury');
const ValueInterpreter = hre.artifacts.require("ValueInterpreter");
const ExchangeAggregator = hre.artifacts.require("ExchangeAggregator");
const TestAdapter = hre.artifacts.require("TestAdapter");
const ChainlinkPriceFeed = hre.artifacts.require('ChainlinkPriceFeed');
const AggregatedDerivativePriceFeed = hre.artifacts.require('AggregatedDerivativePriceFeed');


describe("Dripper", async () => {
  let dripper, usdt, usdi, vault;

  let accounts;
  let governance;
  let governanceAddress;
  let accessControlProxy;
  let user1;


  before('Init',async function(){
    accounts = await ethers.getSigners();
    governance = accounts[19];
    governanceAddress= accounts[19].address;
    user1 = accounts[1].address;
    // user2 = accounts[2].address;
    });


  beforeEach(async () => {
    
    const AccessControlProxy = await ethers.getContractFactory("AccessControlProxy",governance);
    accessControlProxy = await AccessControlProxy.deploy();
    await accessControlProxy.deployed();
    await accessControlProxy.initialize(governanceAddress, governanceAddress, governanceAddress, governanceAddress);
    
    const USDi = await ethers.getContractFactory("USDi",governance);
    usdi = await USDi.deploy();
    await usdi.deployed();
    await usdi.initialize('USDi','USDi',18,accessControlProxy.address);

    const DRIPPER = await ethers.getContractFactory("Dripper",governance);
    dripper = await DRIPPER.deploy();
    await dripper.deployed();
    

    usdt = await ERC20.at(MFC.USDT_ADDRESS);
    await topUpUsdtByAddress(usdtUnits("1000").toString(), dripper.address);



    console.log('deploy Treasury');
    // 国库
    treasury = await Treasury.new();
    treasury.initialize(accessControlProxy.address);

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
    const valueInterpreter = await ValueInterpreter.new(chainlinkPriceFeed.address, aggregatedDerivativePriceFeed.address);


    console.log('deploy TestAdapter');
    testAdapter = await TestAdapter.new(valueInterpreter.address);

    console.log('deploy ExchangeAggregator');
    const exchangeAggregator = await ExchangeAggregator.new([testAdapter.address], accessControlProxy.address);
    const adapters = await exchangeAggregator.getExchangeAdapters();
    let exchangePlatformAdapters = {};
    for (let i = 0; i < adapters.identifiers_.length; i++) {
        exchangePlatformAdapters[adapters.identifiers_[i]] = adapters.exchangeAdapters_[i];
    }
    console.log('deploy Vault');
    // vault = await Vault.new();
    const VAULT = await ethers.getContractFactory("Vault", governance);
    vault = await VAULT.deploy();
    await vault.deployed();

    vault.initialize(usdi.address, accessControlProxy.address, treasury.address, exchangeAggregator.address, valueInterpreter.address);

    await dripper.initialize(accessControlProxy.address, vault.address, MFC.USDT_ADDRESS);

  });

  function usdtUnits(amount) {
    return parseUnits(amount, 6);
  }

  async function emptyDripper() {
    const balance = await usdt.balanceOf(dripper.address);
    console.log("balance = ", balance.toString());
    await dripper.transferToken(usdt.address, balance.toString());
  }

  async function expectApproxCollectOf(amount, fn) {
    const before = (await usdt.balanceOf(vault.address));
    await fn();
    const after = (await usdt.balanceOf(vault.address));
    const collected = parseUnits(after.sub(before).toString(), 0);
    console.log("collected = ", collected);
    console.log("usdtUnits(amount) = ", usdtUnits(amount));
    expect(collected).gte(usdtUnits(amount).mul(998).div(1000));
    expect(collected).lte(usdtUnits(amount).mul(1005).div(1000));
  }

  async function advanceTime(seconds) {
    await hre.ethers.provider.send("evm_increaseTime", [seconds]);
    await hre.ethers.provider.send("evm_mine");
  };

  describe("availableFunds()", async () => {
    it("shows zero available before any duration has been set", async () => {
      await advanceTime(1000);
      const availableFunds = await dripper.availableFunds(); 
      console.log("availableFunds 1 = ", availableFunds);
      expect(availableFunds).to.equal(0);
    });
    it("returns a number after a duration has been set", async () => {
      await dripper.setDripDuration("2000");
      await advanceTime(1000);
      const availableFunds = await dripper.availableFunds(); 
      console.log("availableFunds 2 = ", availableFunds);
      expect(availableFunds).to.equal(usdtUnits("500"));
    });
    it("returns zero if no balance", async () => {
      await dripper.setDripDuration("2000");
      await advanceTime(1000);
      await emptyDripper();
      const availableFunds = await dripper.availableFunds(); 
      console.log("availableFunds 3 = ", availableFunds);
      expect(availableFunds).to.equal(0);
    });
  });

  describe("Drip math", async () => {
    it("gives all funds if collect is after the duration end", async () => {
      await dripper.setDripDuration("20000");
      await advanceTime(20001);
      await expectApproxCollectOf("1000", dripper.collect);
    });
    it("gives 98% of funds if the collect is 98% to the duration", async () => {
      await dripper.setDripDuration("20000");
      await advanceTime(19600);
      await expectApproxCollectOf("980", dripper.collect);
    });
    it("adding funds does not change the current drip rate", async () => {
      await dripper.setDripDuration("20000");
      //await usdt.mintTo(dripper.address, usdtUnits("3000"));
      await topUpUsdtByAddress(usdtUnits("3000").toString(), dripper.address);
      await advanceTime(19600);
      await expectApproxCollectOf("980", dripper.collect);
    });
    it("rounds down the rate", async () => {
      await emptyDripper();
      //await usdt.mintTo(dripper.address, 999); 
      // 1/1000 of a USDC
      await topUpUsdtByAddress("999", dripper.address);
      await dripper.setDripDuration("1000");
      await advanceTime(500);
      // Per block rate should be zero
      await expectApproxCollectOf("0", dripper.collect);
    });
  });

  describe("collect()", async () => {
    it("transfers funds to the vault", async () => {
      await dripper.setDripDuration("20000");
      await advanceTime(1000);
      await expectApproxCollectOf("50", dripper.collect);
    });
    it("collects what is reported by availableFunds()", async () => {
      await dripper.setDripDuration("20000");
      await advanceTime(17890);
      const expected = ((await dripper.availableFunds()) / 1e6).toString();
      await expectApproxCollectOf(expected, dripper.collect);
    });
  });

  describe("collectTokens()", async () => {
    it("transfers funds to governor", async () => {
      let balance = await usdt.balanceOf(dripper.address);
      balance = parseUnits(balance.toString(), 0);
      expect(balance).to.equal(usdtUnits("1000"));
      let beforeBalance = await usdt.balanceOf(governanceAddress);

      await dripper.transferToken(usdt.address, balance);
      balance = await usdt.balanceOf(dripper.address);
      balance = parseUnits(balance.toString(), 0);
      expect(balance).to.equal(0);

      let afterBalance = await usdt.balanceOf(governanceAddress);
      balance = parseUnits(afterBalance.sub(beforeBalance).toString(), 0);
      expect(balance).to.equal(usdtUnits("1000"));
    });
  });

  describe("setDripDuration()", async () => {
    it("transfers funds to governor", async () => {
      await dripper.setDripDuration(1000);
      expect(await dripper.dripDuration()).to.equal(1000);
    });
    it("cannot be set to zero by the public", async () => {
      await expect(
        dripper.setDripDuration(0)
      ).to.be.revertedWith("duration must be non-zero");
    });
  });

  describe("collectAndRebase()", async () => {
    it("transfers funds to the vault and rebases", async () => {
      const vaultRole = await accessControlProxy.VAULT_ROLE();
      // 授权valut 可以调用usdi.changeSupply的权限。
      await accessControlProxy.grantRole(vaultRole, vault.address);
      let mintAmount = BigInt(3e18);
      // mint USDi for external account
      await usdi.mint(user1,mintAmount.toString());

      await vault.connect(governance).addAsset(MFC.USDT_ADDRESS);

      const beforeRct = await usdi.rebasingCreditsPerToken();
      console.log("beforeRct = ", beforeRct.toString());
      await dripper.setDripDuration("20000");
      await advanceTime(10000);
      await expectApproxCollectOf("500", async () => {await dripper.connect(governance).collectAndRebase()});
      const afterRct = await usdi.rebasingCreditsPerToken();
      console.log("afterRct = ", afterRct.toString());
      expect(afterRct).to.be.lt(beforeRct);
    });
  });


});

