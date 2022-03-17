// const { hre } = require('hardhat');
const { expect,assert } = require("chai");
// const AccessControlProxy = hre.artifacts.require('AccessControlProxy');
// const { default: BigNumber } = require("bignumber.js");
const { Contract } = require("ethers");
const { ethers } = require("hardhat");

// const USDi = hre.artifacts.require('USDi');
// const ERC20 = hre.artifacts.require('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');

describe('USDi Test',function(){

    let accounts;
    let usdi;
    let governance;
    let user1;
    let user2;
    let contractAddr;
    let accessControlProxy;


    before('Init',async function(){
        accounts = await ethers.getSigners();
        governance = accounts[19].address;
        user1 = accounts[1].address;
        user2 = accounts[2].address;
        
        const AccessControlProxy = await ethers.getContractFactory("AccessControlProxy",accounts[19]);
        accessControlProxy = await AccessControlProxy.deploy(governance, governance, governance, governance);
        await accessControlProxy.deployed();
        contractAddr = accessControlProxy.address;
        
        const USDi = await ethers.getContractFactory("USDi",accounts[19]);
        usdi = await USDi.deploy();
        await usdi.deployed();
        await usdi.initialize('USDi','USDi',18,accessControlProxy.address);
        
        
    });

    it('Mint USDi to external account1',async function(){
        let mintAmount = BigInt(3e18);
        // mint USDi for external account
        await usdi.mint(user1,mintAmount.toString());
        let user1Balance = await usdi.balanceOf(user1);
        console.log('user1Balance:%d',user1Balance);
        expect(user1Balance.toString()).to.equal(mintAmount.toString());
        let user1CreditsBalance = await usdi.creditsBalanceOf(user1);
        console.log('user1CreditsBalance:',user1CreditsBalance);

        let currSupply = await usdi.totalSupply();
        expect(currSupply.toString()).to.equal(mintAmount.toString());
    });

    it('Mint USDi to contract account',async function(){
        let mintAmount = BigInt(5e18);
        // mint USDi for Contract account
        await usdi.mint(contractAddr,mintAmount.toString());
        let contractBalance = await usdi.balanceOf(contractAddr);
        console.log('contractBalance:%d',contractBalance.toString());
        expect(contractBalance.toString()).to.equal(mintAmount.toString());

        let currSupply = await usdi.totalSupply();
        console.log('After mint to contract,total supply:',currSupply.toString());
        
    });


    it('Change totoal supply to 1.2x',async function(){
        let currSupply = await usdi.totalSupply();
        let newSupply =  BigInt(currSupply * 1.2);
        let rebasingCreditsPerToken = await usdi.rebasingCreditsPerToken();
        let rebasingCredits = await usdi.rebasingCredits();
        console.log('before rebase rebasingCreditsPerToken:',rebasingCreditsPerToken.toString());
        console.log('before rebase rebasingCredits:',rebasingCredits.toString());
        // go to rebase
        await usdi.changeSupply(newSupply);
        rebasingCreditsPerToken = await usdi.rebasingCreditsPerToken();
        rebasingCredits = await usdi.rebasingCredits();
        console.log('after rebase rebasingCreditsPerToken:',rebasingCreditsPerToken.toString());
        console.log('after rebase rebasingCredits:',rebasingCredits.toString());
        
        currSupply = await usdi.totalSupply();
        console.log('currSupply:%s,newSupply:%s',currSupply,newSupply);
        let user1Balance = BigInt(await usdi.balanceOf(user1));
        let contractBalance = BigInt(await usdi.balanceOf(contractAddr));
        console.log('user1Balance:%d,contractBalance:%d',user1Balance,contractBalance.toString());
        expect(user1Balance + contractBalance).to.equal(currSupply);
    });

    it('External contract optOut',async function(){
        let signedUsdi = await usdi.connect(accounts[1]);
        await signedUsdi.rebaseOptOut();

        let currSupply = await usdi.totalSupply();
        let newSupply =  BigInt(currSupply * 5);
        let error;
        try {
            await usdi.changeSupply(newSupply);
        } catch (err) {
            error = err;
            console.log('error:',error.message);
        } finally {
            let expectErrorMsg = 'VM Exception while processing transaction: reverted with reason string \'Invalid change in supply\'';
            expect(error.message).to.equal(expectErrorMsg,'when all accounts not support rebase should revert.');
        }
    });

    it('Mint USDi to external account2',async function(){
        let mintAmount = BigInt(3e18);
        // mint USDi for external account
        await usdi.mint(user2,mintAmount.toString());
        let user2Balance = await usdi.balanceOf(user2);
        console.log('user2Balance:%d',user2Balance);
        expect(user2Balance.toString()).to.equal(mintAmount.toString());

        let user1CreditsBalance = await usdi.creditsBalanceOf(user1);
        console.log('user1CreditsBalance:',user1CreditsBalance);
        
        let user2CreditsBalance = await usdi.creditsBalanceOf(user2);
        console.log('user2CreditsBalance:',user2CreditsBalance);

        let contractCreditsBalance = await usdi.creditsBalanceOf(contractAddr);
        console.log('contractCreditsBalance:',contractCreditsBalance);

        expect(Number(user1CreditsBalance)).to.gt(Number(user2CreditsBalance));
    });

    it('Change totoal supply to 2x',async function(){
        let currSupply = await usdi.totalSupply();
        let newSupply =  BigInt(currSupply * 2);
        let rebasingCreditsPerToken = await usdi.rebasingCreditsPerToken();
        let rebasingCredits = await usdi.rebasingCredits();
        console.log('before rebase rebasingCreditsPerToken:',rebasingCreditsPerToken.toString());
        console.log('before rebase rebasingCredits:',rebasingCredits.toString());
        // go to rebase
        await usdi.changeSupply(newSupply);
        rebasingCreditsPerToken = await usdi.rebasingCreditsPerToken();
        rebasingCredits = await usdi.rebasingCredits();
        console.log('after rebase rebasingCreditsPerToken:',rebasingCreditsPerToken.toString());
        console.log('after rebase rebasingCredits:',rebasingCredits.toString());
        
        currSupply = await usdi.totalSupply();
        console.log('currSupply:%s,newSupply:%s',currSupply,newSupply);
        let user1Balance = BigInt(await usdi.balanceOf(user1));
        let user2Balance = BigInt(await usdi.balanceOf(user2));
        let contractBalance = BigInt(await usdi.balanceOf(contractAddr));
        console.log('user1Balance:%d,user2Balance:%d,contractBalance:%d',user1Balance,user2Balance,contractBalance.toString());
        expect(user1Balance + user2Balance + contractBalance).to.equal(currSupply);
    });

    it('Burn',async function(){
        let user1Balance = BigInt(await usdi.balanceOf(user1));
        await usdi.burn(user1,user1Balance);
        let user2Balance = BigInt(await usdi.balanceOf(user2));
        await usdi.burn(user2,user2Balance);
        let contractBalance = BigInt(await usdi.balanceOf(contractAddr));
        await usdi.burn(contractAddr,contractBalance);

        let currSupply = await usdi.totalSupply();
        console.log('After burn all,total supply:',currSupply);
        expect(Number(currSupply)).to.eq(0);
    });

});
