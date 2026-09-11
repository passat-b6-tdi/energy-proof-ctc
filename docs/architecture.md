# Architecture

## Components

```
  Ethereum Sepolia (source, chain key 1)        Creditcoin CC3 Testnet (102031)
  ┌───────────────────────────────┐             ┌──────────────────────────────────┐
  │ EnergyMeter.sol               │             │ EnergyProofConsumer.sol          │
  │  recordProduction(EnergyParams)│            │  is AttestcoinReader             │
  │  emits EnergyProduced(        │             │  execute(chainKey, block, ...)  │
  │    oracle, producer,          │             │   1. computeQueryId              │
  │    readingId, wattHours)      │             │   2. reject if processed (replay)│
  └──────────────┬────────────────┘             │   3. VERIFIER.verifyAndEmit(...) │
                 │                              │   4. decode tx (EvmV1Decoder)   │
                 │  (1) tx + event log          │      require receiptStatus == 1 │
                 ▼                              │      find EnergyProduced log    │
  ┌───────────────────────────────┐             │      require source == METER    │
  │ worker/watch.ts               │             │   5. bounds-check wattHours     │
  │  poll EnergyProduced          │  (4) submit │   6. LEDGER.credit(...)         │
  │  generateProofFor(txHash) ────┼────proof───▶ └──────────────┬──────────────────┘
  │   - wait attested height      │                            │
  │   - proofBuilder.getProof     │             ┌──────────────▼──────────────────┐
  │  submit to consumer.execute   │             │ EnergyCreditLedger.sol          │
  └───────────────┬───────────────┘             │  credit(producer, wh, readingId,│
                  │                             │         queryId) onlyConsumer   │
                  │  (2) GET proof              │  settled[readingId] guard       │
                  ▼                             │  balanceOf[producer] += wh      │
  ┌───────────────────────────────┐             │  emits SettlementRecorded      │
  │ Attestcoin proof builder      │             └────────────────────────────────┘
  │ prover.cc3-testnet...         │
  │ + NativeQueryVerifier 0x..0FD2 │  (3) attestation reached on Creditcoin
  └───────────────────────────────┘
```

## Flow (happy path)

1. An oracle calls `EnergyMeter.recordProduction(EnergyParams)` on Sepolia. The
   contract emits `EnergyProduced(msg.sender, producer, readingId, wattHours)`.
2. `worker/watch.ts` sees the event, takes the tx hash, and calls the Attestcoin
   SDK: wait until the Sepolia block height is attested on Creditcoin (~8 min),
   then `proofBuilder.getProof(txHash)` returns `{ chainKey, headerNumber,
   txBytes, merkleProof, continuityProof }`.
3. The worker calls `EnergyProofConsumer.execute(uint64 chainKey, uint64 blockHeight,
   bytes encodedTransaction, tuple merkleProof, tuple continuityProof)` on
   Creditcoin with that proof data.
4. `AttestcoinReader` computes `queryId` (`chainKey|blockHeight|txIndex`), rejects
   a replay, calls the `0x..0FD2` precompile `verifyAndEmit`, and requires it to
   return `true`.
5. `EnergyProofConsumer` decodes the verified transaction bytes with
   `EvmV1Decoder`: requires `receiptStatus == 1`, finds the `EnergyProduced` log
   by signature, requires the emitting contract to equal the configured
   `energyMeter` address, and extracts `(oracle, producer, readingId, wattHours)` from
   the log topics/data.
6. It bounds-checks `wattHours` (`0 < wattHours <= MAX_WATT_HOURS`) and calls
   `EnergyCreditLedger.credit(producer, wattHours, readingId, queryId, chainKey,
   blockHeight)`.
7. The ledger checks `!settled[readingId]`, sets it, increments
   `balanceOf[producer]`, stores structured `settlementOf(readingId)` data
   including source chain/block provenance, and emits `SettlementRecorded`.

## Trust model

- **No trust in the worker.** The worker only relays bytes; it cannot forge a
  credit. Every field the ledger acts on comes from a transaction the Attestcoin
  precompile has verified as included in an attested Sepolia block.
- **No trust in the caller of `execute`.** Anyone may submit a valid proof; the
  proof is self-authenticating. Griefing (submitting someone else's proof) only
  credits the rightful producer sooner and burns the caller's gas.
- **Two independent replay guards.** `AttestcoinReader.processedQueries[queryId]`
  (one reading per source transaction) and `EnergyCreditLedger.settled[readingId]`
  (per meter reading).
- **`EnergyCreditLedger.credit` requires `CONSUMER_ROLE`.** Direct settlement is
  impossible.
- **Meter onboarding is permissioned.** `Register` separates the admin,
  registrar, and oracle roles. This controls who may submit source readings;
  it does not replace Attestcoin proof verification.

## Why this fits DePIN

`EnergyMeter` stands in for a metering device / sensor on one network; settlement
and incentive accounting happen on Creditcoin, driven entirely by cross-chain
data that Attestcoin has attested. The cross-chain decision does not trust a
centralised relay; source-reading submission is separately controlled by the
meter's `ORACLE_ROLE`.
