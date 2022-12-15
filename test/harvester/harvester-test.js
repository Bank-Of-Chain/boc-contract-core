const { default: BigNumber } = require("bignumber.js");
const { expect } = require("chai");
const { send } = require("@openzeppelin/test-helpers");
const { deployMockContract } = require('@ethereum-waffle/mock-contract');
const hre = require("hardhat");

const AccessControlProxy = hre.artifacts.require("AccessControlProxy");
const Harvester = hre.artifacts.require("Harvester");
const MockVault = hre.artifacts.require("MockVault");
const MockStrategy = hre.artifacts.require("MockStrategy");
const Mock3rdPoolArtifacts = hre.artifacts.readArtifactSync('Mock3rdPool');


describe("Harvester Test", function () {
    const USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
    const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

    let accounts;
    let mockVault;
    let harvester;
    let governance;
    let user1;
    let user2;
    let accessControlProxy;

    before("Init", async function () {
        accounts = await hre.ethers.getSigners();
        governance = accounts[19].address;
        user1 = accounts[1].address;
        user2 = accounts[2].address;

        accessControlProxy = await AccessControlProxy.new();
        await accessControlProxy.initialize(governance, governance, governance, governance);

        mockVault = await MockVault.new(accessControlProxy.address);
        await impersonates([mockVault.address]);

        await send.ether(accounts[0].address, mockVault.address, 10 * 10 ** 18);
        harvester = await Harvester.new();
        await harvester.initialize(
            accessControlProxy.address,
            mockVault.address,
            USDT,
            mockVault.address,
        );
    });

    async function impersonates(targetAccounts) {
        for (let i = 0; i < targetAccounts.length; i++) {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [targetAccounts[i]],
            });
        }
    }

    it("Harvester the initialization function cannot be executed twice", async function () {
        await expect(
            harvester.initialize(accessControlProxy.address, mockVault.address, USDT, mockVault.address),
        ).to.be.revertedWith("Initializable: contract is already initialized");
    });

    it("Harvester base info check", async function () {
        const profitReceiver = await harvester.profitReceiver();
        expect(profitReceiver).to.be.equals(mockVault.address);
        const sellTo = await harvester.sellTo();
        expect(sellTo).to.be.equals(USDT);
        const vaultAddress = await harvester.vaultAddress();
        expect(vaultAddress).to.be.equals(mockVault.address);
    });

    it("Harvester should can set profit receiver", async function () {
        // user1 no access
        await expect(harvester.setProfitReceiver(user1, { from: user1 })).to.be.reverted;
        await harvester.setProfitReceiver(user1, { from: governance });
        const profitReceiver = await harvester.profitReceiver();
        expect(profitReceiver).to.be.equals(user1);
    });

    it("Harvester should can change sellTo token", async function () {
        // user1 no access
        await expect(harvester.setSellTo(DAI, { from: user1 })).to.be.reverted;
        await harvester.setSellTo(DAI, { from: governance });
        const sellTo = await harvester.sellTo();
        expect(sellTo).to.be.equals(DAI);
    });

    it("Harvester call collect should call strategy's harvest", async function () {
        const mock3rdPool = await deployMockContract(accounts[0], Mock3rdPoolArtifacts.abi);
        await mock3rdPool.mock.underlyingToken.returns(USDT);
        const mockStrategy = await MockStrategy.new();
        await mockStrategy.initialize(mockVault.address, harvester.address, mock3rdPool.address);
        await harvester.collect([mockStrategy.address], { from: governance });
    });
});
