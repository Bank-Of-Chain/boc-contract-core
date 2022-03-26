const { expect,assert } = require("chai");
const {Contract, ContractFactory, utils, Wallet} = require('ethers');

const hre = require("hardhat");
const { default: BigNumber } = require('bignumber.js');
const {MockProvider} = require('@ethereum-waffle/provider');
const {deployMockContract} = require('@ethereum-waffle/mock-contract');
const { ethers } = require("hardhat");

const {topUpUsdtByAddress} = require('../../utilities/top-up-utils');

// const MockVaultArtifacts = hre.artifacts.readArtifactSync('MockVault');
// const MockStrategyArtifacts = hre.artifacts.readArtifactSync('MockStrategy');
const Mock3rdPoolArtifacts = hre.artifacts.readArtifactSync('Mock3rdPool');
const AccessControlProxy = hre.artifacts.require('AccessControlProxy');
const MockVault = hre.artifacts.require('MockVault');
const MockStrategy = hre.artifacts.require('MockStrategy');
const ERC20 = hre.artifacts.require('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');

describe('Strategy test',function(){

    const USDT = '0xdAC17F958D2ee523a2206206994597C13D831ec7';
    const CRV = '0xD533a949740bb3306d119CC777fa900bA034cd52';
    const CVX = '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B';
    const lendAmount = 500 * 1e6;
    const sharePrice = 1.01;
    const lpAmount = 1000;

    let sender;
    let contractFactory;
    let accessControlProxy;
    let mock3rdPool;
    let mockStrategy;
    let mockVault;
    let harvester;

    

    it('INIT', async function () {
        // [sender] = new MockProvider().getWallets();
        let accounts = await ethers.getSigners();
        sender = accounts[0];
        harvester = accounts[1];

        await topUpUsdtByAddress(100000 * 1e6,sender.address);

        accessControlProxy = await AccessControlProxy.new(sender.address,sender.address,sender.address,sender.address);
        console.log('accessControlProxy:',accessControlProxy.address);

        mockVault = await MockVault.new(accessControlProxy.address);
        console.log('mockVault:',mockVault.address);
        await accessControlProxy.grantRole(await accessControlProxy.VAULT_ROLE(),mockVault.address);

        mock3rdPool = await deployMockContract(sender,Mock3rdPoolArtifacts.abi);
        console.log('mock3rdPool:',mock3rdPool.address);
        await mock3rdPool.mock.underlyingToken.returns(USDT);

        mockStrategy = await MockStrategy.new();
        console.log('mockStrategy:',mockStrategy.address);

        await mockStrategy.initialize(mockVault.address, harvester, mock3rdPool.address);
    });

  
    it('Test get version',async function(){
        const version = await mockStrategy.getVersion();
        console.log('version:',version);
        expect(version).equals('0.0.1');
    });

    it('Test get name',async function(){
        const name = await mockStrategy.name();
        console.log('name:',name);
        expect(name).equals('MockStrategy');
    });

    it('Test get protocol ID',async function(){
        const protocolId = await mockStrategy.protocol();
        console.log('protocolId:',protocolId);
        expect(Number(protocolId)).to.eq(23);
    });

    it('Test get vault',async function(){
        const vault = await mockStrategy.vault();
        console.log('vault:',vault);
        expect(vault).equals(mockVault.address);
    });

    it('Test get wants info',async function(){
        const wantsInfo = await mockStrategy.getWantsInfo();
        console.log('wantsInfo:',wantsInfo);
        expect(wantsInfo[0][0]).equals(await mock3rdPool.underlyingToken());
        expect(Number(wantsInfo[1])).to.eq(1);
    });

    it('Test 3rd pool assets',async function(){
        await mock3rdPool.mock.totalSupply.returns(utils.parseEther('5000'));
        await mock3rdPool.mock.decimals.returns(18);
        await mock3rdPool.mock.pricePerShare.returns(utils.parseEther(sharePrice.toString()));
        const poolAssets = new BigNumber(await mockStrategy.get3rdPoolAssets());
        console.log('poolAssets:',poolAssets.toString());
        // expect(Number(utils.formatEther(poolAssets.toString()))).to.eq(5050);
    });


    it('Vault lend to strategy',async function(){
        const tokenUSDT = await ERC20.at(USDT);
        await tokenUSDT.transfer(mockVault.address,1000 * 1e6);
        console.log('vault usdt balance:%d',await tokenUSDT.balanceOf(mockVault.address));
        console.log('sender usdt balance:%d',await tokenUSDT.balanceOf(sender.address));

        await mock3rdPool.mock.deposit.returns();
        await mockVault.lend(mockStrategy.address,[USDT],[lendAmount]);
        let vaultUSDTBalance = await tokenUSDT.balanceOf(mockVault.address);
        console.log('vault usdt balance:%d',vaultUSDTBalance);
        expect(Number(vaultUSDTBalance)).to.eq(1000 * 1e6 - lendAmount);        
    });

    it('Claim rewards',async function(){
        await mock3rdPool.mock.getPendingRewards.returns([CRV,CVX],[utils.parseEther('2.7'),utils.parseEther('1.6')]);
        const result = await mockStrategy.getPendingRewards();
        console.log('pending rewards:',result);
        const cvxAmount = Number(result[1][0]);
        const crvAmount = Number(result[1][1]);
        console.log('cvxAmount:%d,crvAmount:%d',cvxAmount,crvAmount);
        expect(cvxAmount).to.eq(2.7e18);
        expect(crvAmount).to.eq(1.6e18);

        await mock3rdPool.mock.balanceOf.returns(lpAmount);
        // Because there is no real receipt of the rewards, fill in 0 to prevent transfer errors 
        await mock3rdPool.mock.claim.returns([0,0]);    
        await mockStrategy.harvest();
    });

    it('Vault redeem from strategy',async function(){
        const estimatedTotalAssets = await mockStrategy.estimatedTotalAssets();
        console.log('estimatedTotalAssets:',estimatedTotalAssets.toString());
        expect(Number(estimatedTotalAssets)).to.eq(Number(sharePrice * lpAmount));
        
        await mock3rdPool.mock.withdraw.returns([USDT],[0]);
        await mockVault.redeem(mockStrategy.address,estimatedTotalAssets);
        const tokenUSDT = await ERC20.at(USDT);
        let vaultUSDTBalance = await tokenUSDT.balanceOf(mockVault.address);
        console.log('vault usdt balance:%d',vaultUSDTBalance);
        expect(Number(vaultUSDTBalance)).to.eq(1000 * 1e6);
    });
});