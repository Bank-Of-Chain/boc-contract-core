require("dotenv").config();

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require('@nomiclabs/hardhat-truffle5');
require("hardhat-gas-reporter");
require("solidity-coverage");
require('hardhat-contract-sizer');
// require('hardhat-spdx-license-identifier');
const {
  removeConsoleLog
} = require('hardhat-preprocessor');

let keys = {}
try {
    keys = require('./dev-keys.json');
} catch (error) {
    keys = {
        alchemyKey: {
            dev: process.env.CHAIN_KEY
        }
    }
}

const DEFAULT_BLOCK_GAS_LIMIT = 30000000;

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {

  networks: {
    hardhat: {
      forking: {
        //url: "https://mainnet.infura.io/v3/" + keys.infuraKey,
        url: 'https://eth-mainnet.alchemyapi.io/v2/' + keys.alchemyKey.dev,
        // url: 'https://eth-mainnet.alchemyapi.io/v2/LkaC5kaCGk8i5CIzO1kkuJrw3186Nkza',
        blockNumber: 14486750, // <-- edit here
      },
      blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
      timeout: 1800000,
      allowUnlimitedContractSize: true,
    },
    localhost: {
      url: 'http://localhost:8545',
      allowUnlimitedContractSize: true,
      // GasPrice used when performing blocking, in wei
      // gasPrice: 100 * 10 ** 9,
      timeout: 1800000,

      /*
        notice no mnemonic here? it will just use account 0 of the hardhat node to deploy
        (you can put in a mnemonic here to set the deployer locally)
      */
    },
    ropsten: {
      url: process.env.ROPSTEN_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
  preprocess: {
    eachLine: removeConsoleLog(bre => bre.network.name !== 'hardhat' && bre.network.name !== 'localhost'),
  },
  gasReporter: {
    enabled: true,
    currency: 'USD',
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  solidity: {
    compilers: [{
      version: '0.6.12',
      settings: {
        optimizer: {
          details: {
            yul: false,
          },
          enabled: true,
          runs: 200
        },
      },

    },
    {
      version: '0.8.3',
      settings: {
        optimizer: {
          details: {
            yul: true,
          },
          enabled: true,
          runs: 200
        },
      },
    },
    ],
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
  // spdxLicenseIdentifier: {
  //   overwrite: true,
  //   runOnCompile: true,
  // }
};
