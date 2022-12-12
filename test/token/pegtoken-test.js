const { default: BigNumber } = require("bignumber.js");
const { expect } = require("chai");
const { send } = require("@openzeppelin/test-helpers");
const hre = require("hardhat");


const AccessControlProxy = hre.artifacts.require("AccessControlProxy");
const PegToken = hre.artifacts.require("PegToken");
const MockVault = hre.artifacts.require("MockVault");

describe("PegToken Test", function () {
    const TOKEN_NAME = "USD Peg Token";
    const TOKEN_SYMBOL = "USDi";
    const TOKEN_DECIMALS = 18;

    let accounts;
    let mockVault;
    let pegToken;
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
        pegToken = await PegToken.new();
        await pegToken.initialize(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DECIMALS,
            mockVault.address,
            accessControlProxy.address,
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

    it("PegToken the initialization function cannot be executed twice", async function () {
        await expect(
            pegToken.initialize(
                TOKEN_NAME,
                TOKEN_SYMBOL,
                TOKEN_DECIMALS,
                mockVault.address,
                accessControlProxy.address,
            ),
        ).to.be.revertedWith("Initializable: contract is already initialized");
    });

    it("PegToken base info check", async function () {
        const tokenName = await pegToken.name();
        expect(tokenName).to.equals(TOKEN_NAME);
        const tokenSymbol = await pegToken.symbol();
        expect(tokenSymbol).to.equals(TOKEN_SYMBOL);
        const tokenDecimals = await pegToken.decimals();
        expect(Number(tokenDecimals)).to.eq(TOKEN_DECIMALS);
    });

    it("PegToken all functions should available when unpaused", async function () {
        // mint
        const user1Shares = new BigNumber(100 * 10 ** 27);
        await pegToken.mintShares(user1, user1Shares, { from: mockVault.address });
        const user1ActualShares = new BigNumber(await pegToken.sharesOf(user1));
        expect(user1ActualShares.toFixed()).to.equals(user1Shares.toFixed());
        const totalShares = new BigNumber(await pegToken.totalShares());
        expect(user1ActualShares.toFixed()).to.equals(totalShares.toFixed());
        // approve
        const approveToUser2Amount = new BigNumber(20 * 10 ** 18);
        await pegToken.approve(user2, approveToUser2Amount, { from: user1 });
        let user2Allowance = new BigNumber(await pegToken.allowance(user1, user2));
        expect(user2Allowance.toFixed()).to.equals(approveToUser2Amount.toFixed());
        // transfer
        const transferToUser2Amount = new BigNumber(10 * 10 ** 18);
        await pegToken.transferFrom(user1, user2, transferToUser2Amount, { from: user2 });
        user2Allowance = new BigNumber(await pegToken.allowance(user1, user2));
        let user2Balance = new BigNumber(await pegToken.balanceOf(user2));
        expect(user2Allowance.toFixed()).to.equals(
            (approveToUser2Amount - transferToUser2Amount).toFixed(),
        );
        expect(user2Balance.toFixed()).to.equals(transferToUser2Amount.toFixed());
        // increaseAllowance & decreaseAllowance
        await pegToken.increaseAllowance(user2, new BigNumber(30 * 10 ** 18), { from: user1 });
        user2Allowance = new BigNumber(await pegToken.allowance(user1, user2));
        expect(user2Allowance.toFixed()).to.equals(new BigNumber(40 * 10 ** 18).toFixed());
        await pegToken.decreaseAllowance(user2, new BigNumber(40 * 10 ** 18), { from: user1 });
        user2Allowance = new BigNumber(await pegToken.allowance(user1, user2));
        expect(Number(user2Allowance.toFixed())).to.equals(0);
        // burn
        await pegToken.burnShares(user2, new BigNumber(user2Balance * 10 ** 9), {
            from: mockVault.address,
        });
        user2Balance = new BigNumber(await pegToken.sharesOf(user2));
        expect(Number(user2Balance.toFixed())).to.eq(0);
    });

    it("PegToken all functions should unavailable when paused", async function () {
        await pegToken.changePauseState(true, { from: governance });
        await expect(pegToken.approve(accounts[18].address, 100)).to.be.revertedWith(
            "No operate during pause.",
        );
        await expect(
            pegToken.burnShares(user1, new BigNumber(10 ** 27), { from: mockVault.address }),
        ).to.be.revertedWith("No operate during pause.");
        await expect(
            pegToken.mintShares(user2, new BigNumber(10 ** 27), { from: mockVault.address }),
        ).to.be.revertedWith("No operate during pause.");
        await expect(
            pegToken.transfer(user2, new BigNumber(10 ** 18), { from: user1 }),
        ).to.be.revertedWith("No operate during pause.");
        await pegToken.changePauseState(false, { from: governance });
    });
});
