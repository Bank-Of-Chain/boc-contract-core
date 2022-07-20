## Desc

This project is the core project of Bank Of Chain Protocol,  includes the implementation of Vault, VaultBuffer, BaseStrategy, BaseClaimableStrategy, AccessControl, ExchangeAggregator, ValueInterpreter, Harvester and usdi core contracts.

The project is developed using the [Hardhat framework.](https://hardhat.org/) The RPC node service uses [Alchemy](https://www.alchemy.com/).

## Test

First you need to install node dependencies:

```bash
npm install
```

or

```bash
yarn install
```

Second you should register a account from  [Alchemy](https://www.alchemy.com/) ,and create ‘dev-keys.json’ file ，paste the key from Alchemy:

```json
{
    "alchemyKey": {
        "dev": "XX",
        "mumbai": "XX",
        "prod": "XX"
    }
}
```

Finally you can test ：

```bash
npx hardhat test test/token/usdi-test.js
```

## Publish

Run command in the root directory

```bash
npm publish
```

## Usage

Dependent project run command:

```bash
npm i boc-contract-core
```