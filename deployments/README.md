# Deployments

Record every deployment here: network, contract, address, deploy tx, commit.

## CC3 Testnet (Creditcoin, EVM chain id 102031)

| Contract | Address | Deploy tx | Commit |
| --- | --- | --- | --- |
| EvmV1Decoder (linked library) | `0xaDcDaBD5b96Af2c89829128321d913CF939d8604` | [0x0f49ede6…](https://creditcoin-testnet.blockscout.com/tx/0x0f49ede6ae9ae76228601bc205c88f225c13aea725121334f238add26c405fcf) | local deployment |
| EnergyCreditLedger | `0x100FEb2D822CBb32C4e8f047D43615AC8851Ed79` | recorded in deploy output | local deployment |
| EnergyProofConsumer | `0x9e3743dEC51b82BD83d7fF7557650BF1C75ee096` | recorded in deploy output | local deployment |

## Ethereum Sepolia (chain id 11155111, Attestcoin chain key 1)

| Contract | Address | Deploy tx | Commit |
| --- | --- | --- | --- |
| EnergyMeter | `0x0d1b7c614e07B47153293469d356b6bA80978BF1` | [0xd095e293…](https://sepolia.etherscan.io/tx/0xd095e2934cc373dbaf69eef758f573621ccb46cdc71237002fe7ed46a1a3117c) | local deployment |

## Deploy order and verification

The deployment helpers use Foundry's `--broadcast --verify` flow. Each receipt is
submitted to Blockscout immediately after deployment. The instance-specific
Blockscout API URLs do not require an API key.

Before deploying, import a funded deployer into the Foundry keystore and set its
name and address in `.env`:

`cast wallet import deployer --interactive`

`DEPLOYER_ACCOUNT="deployer"`

1. Deploy and verify our `EvmV1Decoder` library on CC3 Testnet once:

   `npm run deploy:decoder`

   Save the printed address as `EVM_V1_DECODER_ADDRESS` in `.env`.

2. Deploy and verify `EnergyMeter` on Sepolia:

   `npm run deploy:meter`

   Save the printed address as `ENERGY_METER_ADDRESS` in `.env`.

3. Deploy and verify `EnergyCreditLedger` and the linked
   `EnergyProofConsumer` on CC3 Testnet:

   `npm run deploy:creditcoin`

   The script links the decoder address from `.env`, grants `CONSUMER_ROLE`,
   and prints the ledger and consumer addresses. Save them in `.env`.

4. Verify `hasRole(CONSUMER_ROLE, consumer)` on-chain and fill in the tables
   above.

For a manual contract deployment, the essential flags are:

`forge create <path>:<contract> --broadcast --verify --verifier blockscout --verifier-url <explorer>/api/`

## Verified demo run

The live demo used 10 source readings from 3 producers. The aggregate result was
12,975 Wh settled across 10 readings. The first proof for the source transaction
below settled successfully; submitting the same proof again reverted with
`QueryAlreadyProcessed` and left the ledger unchanged.

- Source transaction: [0x9b4c80…](https://sepolia.etherscan.io/tx/0x9b4c80e62b5cf9e3342a63ac71636204ce8bdec5ed6fcc1f4e713e3d47b55940)
- Reading ID: `0x4febb434d78954225fd1b76a26f969912f8146d6393dd078b9d16c6ab9be806c`
- Successful settlement: [0xb8b4cc…](https://creditcoin-testnet.blockscout.com/tx/0xb8b4cc971c6a6497f157f50ca9543261900d55843c8162632f2408eb685f1065)
- Replay rejection: [0x9df205…](https://creditcoin-testnet.blockscout.com/tx/0x9df20568f6787feac0a91d550782b96c27778df46912ee215b99e4d85133b302)

To reproduce the replay check:

`npm run demo:replay -- 0x9b4c80e62b5cf9e3342a63ac71636204ce8bdec5ed6fcc1f4e713e3d47b55940`
