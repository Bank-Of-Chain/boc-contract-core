const { expect } = require("chai");
const { ethers } = require("hardhat");
const ERC20 = hre.artifacts.require('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');
const MFC = require("../mainnet-fork-test-config");
const {topUpUsdtByAddress} = require('../../utilities/top-up-utils');
const { parseUnits } = require("ethers").utils;
const MockVault = hre.artifacts.require('MockVault');



describe("Dripper", async () => {
  let dripper, usdt, mockVault;

  let accounts;
  let governance;
  let governanceAddress;
  let accessControlProxy;


  before('Init',async function(){
    accounts = await ethers.getSigners();
    governance = accounts[19];
    governanceAddress= accounts[19].address;
    });


  beforeEach(async () => {
    
    const AccessControlProxy = await ethers.getContractFactory("AccessControlProxy",governance);
    accessControlProxy = await AccessControlProxy.deploy();
    await accessControlProxy.deployed();
    await accessControlProxy.initialize(governanceAddress, governanceAddress, governanceAddress, governanceAddress);

    const DRIPPER = await ethers.getContractFactory("Dripper",governance);
    dripper = await DRIPPER.deploy();
    await dripper.deployed();
    

    usdt = await ERC20.at(MFC.USDT_ADDRESS);
    await topUpUsdtByAddress(usdtUnits("1000").toString(), dripper.address);

    
    console.log('deploy mockVault');
    mockVault = await MockVault.new(accessControlProxy.address);

    await dripper.initialize(accessControlProxy.address, mockVault.address, MFC.USDT_ADDRESS);

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
    const before = (await usdt.balanceOf(mockVault.address));
    await fn();
    const after = (await usdt.balanceOf(mockVault.address));
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

  describe("setToken()", async () => {
    it("token cannot be set when last token's balance is not zero", async () => {
      const balance = await usdt.balanceOf(dripper.address);
      console.log("balance1 = ", balance);
      await expect(
        dripper.setToken(MFC.DAI_ADDRESS)
      ).to.be.revertedWith("balance must be zero");
    });
    
    it("token can be set when last token's balance is zero", async () => {
      await emptyDripper();
      expect(await dripper.token()).to.equal(MFC.USDT_ADDRESS);
      await dripper.setToken(MFC.DAI_ADDRESS);
      expect(await dripper.token()).to.equal(MFC.DAI_ADDRESS);
    });
  });

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
      await dripper.setDripDuration("20000");
      await advanceTime(10000);
      await expectApproxCollectOf("500", async () => {await dripper.collectAndRebase()});
    });
  });


});

