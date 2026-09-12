# Deployments and live evidence

## Main application

[Open EnergyProof](https://energy-proof.b0gdaniy.xyz/)

## Contracts

| Contract | Network | Address |
| --- | --- | --- |
| EnergyMeter | Ethereum Sepolia | `0x0d1b7c614e07B47153293469d356b6bA80978BF1` |
| EvmV1Decoder | Creditcoin CC3 Testnet | `0xaDcDaBD5b96Af2c89829128321d913CF939d8604` |
| EnergyCreditLedger | Creditcoin CC3 Testnet | `0x100FEb2D822CBb32C4e8f047D43615AC8851Ed79` |
| EnergyProofConsumer | Creditcoin CC3 Testnet | `0x9e3743dEC51b82BD83d7fF7557650BF1C75ee096` |

The consumer has `CONSUMER_ROLE` on the ledger. Wiring transaction:
[0x284e3f…](https://creditcoin-testnet.blockscout.com/tx/0x284e3f2059891c3be0d51af44aaecc68157d5176395a066ebbf8380e591e340).

## Demo evidence

- 10 readings settled from 3 producers.
- Total settled production: `12,975 Wh`.
- Source transaction: [Sepolia](https://sepolia.etherscan.io/tx/0x9b4c80e62b5cf9e3342a63ac71636204ce8bdec5ed6fcc1f4e713e3d47b55940).
- Successful settlement: [Creditcoin](https://creditcoin-testnet.blockscout.com/tx/0xb8b4cc971c6a6497f157f50ca9543261900d55843c8162632f2408eb685f1065).
- Rejected replay: [Creditcoin](https://creditcoin-testnet.blockscout.com/tx/0x9df20568f6787feac0a91d550782b96c27778df46912ee215b99e4d85133b302).

The replay reverted with `QueryAlreadyProcessed`. The producer balance stayed
at `3,075` and `totalCredited` stayed at `12,975`.
