# EnergyProof CTC

Cross-chain energy settlement verified through the **Attestcoin Protocol** on Creditcoin.

Submission for **BUIDL CTC 2026 Fall** — _BUIDL For The Real World_ (Creditcoin & Credit Labs). Track: **DePIN**.

## What it does

A metering device records an energy-production reading on one chain (Ethereum
Sepolia). EnergyProof verifies that reading on Creditcoin through the Attestcoin
readability path — attestation quorum, then a Merkle + continuity proof checked by
the `0x…0FD2` NativeQueryVerifier precompile — and only then records exactly one
energy credit for the producer. No centralised oracle operator sits between the
sensor event and the on-chain credit.

**Core invariant:** no ledger state changes before the Attestcoin proof verifies.
A replayed or invalid proof credits nothing.

## Layout

| Path                                                 | Chain      | Contract                                                                                                                                               |
| ---------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `contracts/source-chain/EnergyMeter.sol`             | Sepolia    | `recordProduction(EnergyParams)` emits `EnergyProduced(address indexed oracle, address indexed producer, bytes32 indexed readingId, uint32 wattHours)` |
| `contracts/creditcoin-chain/AttestcoinReader.sol`    | Creditcoin | Base: precompile verify + per-tx replay guard                                                                                                          |
| `contracts/creditcoin-chain/EnergyProofConsumer.sol` | Creditcoin | Decodes the verified tx, validates it, calls the ledger                                                                                                |
| `contracts/creditcoin-chain/EnergyCreditLedger.sol`  | Creditcoin | Records credits; per-reading replay guard; `CONSUMER_ROLE`-only                                                                                        |
| `worker/`                                            | off-chain  | Watches the source event, builds the proof, submits it                                                                                                 |

Full flow: [`docs/architecture.md`](docs/architecture.md). Diagrams: [`docs/diagrams.md`](docs/diagrams.md).
Attestcoin integration writeup: [`docs/attestcoin-integration.md`](docs/attestcoin-integration.md).
Security invariants → tests: [`docs/security-invariants.md`](docs/security-invariants.md).
Contract NatSpec reference: [`docs/contract-reference.md`](docs/contract-reference.md).
Published documentation: [EnergyProof CTC on GitHub Pages](https://passat-b6-tdi.github.io/energy-proof-ctc/).
GitBook mirror: [b0gdaniy.gitbook.io/energy-proof](https://b0gdaniy.gitbook.io/energy-proof/).

## Demo UI

The standalone dashboard lives in [`ui/`](ui/). After deployment it
reads source events and settlement state directly from Sepolia and Creditcoin.
Before addresses are filled, it remains in an explicitly labelled presentation mode.

```sh
npm run ui
# open http://localhost:4173
```

Click a reading to inspect its provenance. The `ui/config.js` file contains the
public RPC endpoints and deployment address slots; URL parameters can override
them for a hosted demo.

## Quickstart

```sh
# prerequisites: foundry, node >= 20
npm install
forge install foundry-rs/forge-std   # if lib/forge-std is absent
forge build
forge test
```

Live testnet deployments and an end-to-end replay-protection result are recorded
in [`deployments/README.md`](deployments/README.md).
Copy `.env.example` to `.env` and fill in an RPC for Sepolia plus a funded private key
(CC3 testnet CTC from the Creditcoin Discord faucet).

## Attestcoin references

- Docs: <https://docs.creditcoin.org/creditcoin-usc>
- Chains / environments: <https://docs.creditcoin.org/creditcoin-usc/usc-chains-environments>
- SDK: `@gluwa/usc-sdk` (USC == Attestcoin; the packages keep the old name)
- Examples this build studied: <https://github.com/gluwa/attestcoin-protocol-examples>

## Live demo result

The demo settled 10 readings from 3 producers for **12,975 Wh**. A second
submission of the same proof was rejected by `QueryAlreadyProcessed`; the
producer balance remained `3,075` and `totalCredited` remained `12,975`.

- Source reading: [Sepolia transaction](https://sepolia.etherscan.io/tx/0x9b4c80e62b5cf9e3342a63ac71636204ce8bdec5ed6fcc1f4e713e3d47b55940)
- Successful settlement: [Creditcoin transaction](https://creditcoin-testnet.blockscout.com/tx/0xb8b4cc971c6a6497f157f50ca9543261900d55843c8162632f2408eb685f1065)
- Rejected replay: [Creditcoin transaction](https://creditcoin-testnet.blockscout.com/tx/0x9df20568f6787feac0a91d550782b96c27778df46912ee215b99e4d85133b302)

## Security

This is a testnet prototype. Do not use it for production settlement without
an independent smart-contract audit and a production-grade role/governance
setup. Report security issues privately through the repository owner.

## License

MIT
