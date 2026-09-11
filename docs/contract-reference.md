# Contract reference

The Solidity contracts are documented with NatSpec. Generate the full Foundry
reference locally with:

```sh
npm run docs:contracts
```

This runs `forge doc` and writes the generated mdBook to
`docs/generated-contracts/`. Serve it locally with:

```sh
forge doc --out docs/generated-contracts --serve --port 4000
```

The generated directory is intentionally excluded from Git because it is a
build artifact. The source of truth is the NatSpec in `contracts/`.

## Contracts

### `EnergyMeter`

Source-chain meter for bounded production readings. An account with
`ORACLE_ROLE` submits `EnergyParams`; every unique `readingId` emits one
`EnergyProduced` event.

### `Register`

Role registry inherited by `EnergyMeter`:

`DEFAULT_ADMIN_ROLE` → `REGISTER_ROLE` → `ORACLE_ROLE`.

### `AttestcoinReader`

Creditcoin base contract that verifies a source transaction through the native
Attestcoin verifier and rejects a processed `queryId`.

### `EnergyProofConsumer`

Validates the verified source transaction, requires exactly one event from the
configured `EnergyMeter`, checks the event fields, and forwards the settlement
with source provenance to the ledger.

### `EnergyCreditLedger`

Creditcoin settlement ledger. Only `CONSUMER_ROLE` can create credits, and each
`readingId` can be settled once. `settlementOf(readingId)` exposes the producer,
amount, query ID, source chain key, and source block height.

### Interfaces

- `IEnergyCreditLedger` defines the settlement ABI and provenance record.
- `INativeQueryVerifierExpanded` defines the Attestcoin precompile calls used by
  `AttestcoinReader`.

## Foundry reference

- [`forge doc` command reference](https://getfoundry.sh/reference/forge/doc)
- [`forge inspect` ABI and NatSpec reference](https://getfoundry.sh/reference/forge/forge-inspect)
