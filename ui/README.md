# EnergyProof demo UI

This is a deliberately dependency-free dashboard. Configure
deployed addresses in `config.js` and it reads `EnergyProduced` events from
Sepolia plus settlement state and totals from Creditcoin over JSON-RPC.
The configured native currencies are ETH on Sepolia (`11155111`) and tCTC on
Creditcoin Testnet (`102031`).

Run it from the repository root with:

```sh
npm run ui
```

The source event reader tries several public Sepolia JSON-RPC endpoints in order
and falls back to the public Sepolia Blockscout indexer when providers omit
historical receipts or logs. Creditcoin currently exposes one official HTTPS
testnet endpoint, so its reads fail clearly rather than silently switching to a
different network.

The page is read-only in live mode. The worker remains responsible for creating
the source reading and submitting the Attestcoin proof. With empty addresses,
the page shows an empty state and explicitly reports that live mode is unavailable.

## Replay evidence

Use an already settled source transaction to produce the security evidence:

```sh
npm run demo:replay -- <settled-source-transaction-hash>
```

The command submits the same proof again, expects `QueryAlreadyProcessed`, and
checks that the producer balance and `totalCredited` are unchanged.
