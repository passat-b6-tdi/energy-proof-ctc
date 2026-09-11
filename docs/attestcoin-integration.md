# Attestcoin Protocol integration

This is the technical documentation required by the BUIDL CTC submission rules:
what is set up, and how the project uses the Attestcoin Protocol as a core feature.

> Status: verified on Creditcoin CC3 Testnet. Deployment addresses and a live
> end-to-end replay test are recorded in `deployments/README.md`.

## Where Attestcoin sits in the design

EnergyProof's entire settlement decision depends on Attestcoin readability. The
Creditcoin contract `EnergyProofConsumer` cannot credit anyone without a proof
that the NativeQueryVerifier precompile accepts. Attestcoin is not a side feature
that could be removed — remove it and there is no verified input, so no credit.

- **Primitive used:** readability (attestation + transaction proving). Writability
  is out of scope for this season and unused.
- **Source chain:** Ethereum Sepolia, Attestcoin chain key `1`.
- **Precompile:** `INativeQueryVerifier` at
  `0x0000000000000000000000000000000000000FD2` on Creditcoin CC3 Testnet.
- **Off-chain:** `@gluwa/usc-sdk` proof builder against
  `https://prover.cc3-testnet.creditcoin.network`.

## On-chain: how the proof is consumed

`consumer.execute(uint64 chainKey, uint64 blockHeight, bytes encodedTransaction,
tuple merkleProof, tuple continuityProof)`:

1. Compute a replay key `queryId = keccak256(chainKey, blockHeight, txIndex)`
   where `txIndex = VERIFIER.calculateTxIndex(merkleProof)`. Revert if seen.
2. `VERIFIER.verifyAndEmit(chainKey, blockHeight, encodedTransaction,
   {root, siblings}, {lowerEndpointDigest, roots})`. Revert unless it returns
   `true`. This is the Attestcoin check: inclusion in an attested source block
   plus attestation-chain continuity.
3. Mark `processedQueries[queryId] = true`, emit `QueryProcessed`.
4. Hand the now-verified transaction bytes to `EnergyProofConsumer`.

`EnergyProofConsumer._onVerifiedTransaction` then, using
`@gluwa/usc-contracts` `EvmV1Decoder` on the verified bytes:

- `getTransactionType` + `isValidTransactionType` — sanity on the tx envelope.
- `decodeReceiptFields(...).receiptStatus == 1` — the source tx must have
  succeeded; a reverted `recordProduction()` call settles nothing.
- `getLogsByEventSignature(receipt, ENERGY_PRODUCED_SIG)` — find the
  `EnergyProduced` log; revert if absent. The source transaction must contain
  exactly one matching log, so one reading is processed per source transaction.
- `log.address_ == energyMeter` — the log must come from our metering contract,
  not any other contract that emits the same signature.
- `log.topics == [sig, oracle, producer, readingId]`, `log.data == abi.encode(wattHours)`
  — shape check, then extract the four event fields.
- `0 < wattHours <= MAX_WATT_HOURS` — domain bounds.
- `EnergyCreditLedger.credit(producer, wattHours, readingId, queryId, chainKey,
  blockHeight)` — records the credit under `CONSUMER_ROLE`; the structured
  `settlementOf(readingId)` value includes source chain/block provenance, and
  the ledger additionally rejects a repeated `readingId`.

Two independent replay guards: `processedQueries[queryId]` (per source
transaction) and `settled[readingId]` (per meter reading).

## Off-chain: how the proof is built

`worker/watch.ts` (see also `worker/produce.ts`):

1. Poll Sepolia for `EnergyProduced` via `queryFilter`; dedupe by tx hash.
2. `generateProofFor(txHash, chainKey=1, PROOF_BUILDER_URL, creditcoinRpc, sepoliaRpc)`:
   - `sepoliaRpc.getTransaction(txHash)` → block number.
   - `PrecompileChainInfoProvider(creditcoinRpc).getLatestAttestedHeightAndHash(1)`.
   - `ProofBuilder(1, PROOF_BUILDER_URL).waitUntilHeightAttested(1, blockNumber, 15_000, 1_200_000)`
     — typically ~8 minutes.
   - `proofBuilder.getProof(txHash)` → `{ chainKey, headerNumber, txBytes,
     merkleProof{root,siblings}, continuityProof{lowerEndpointDigest,roots} }`.
3. Gas: try `estimateGas`; on the known precompile estimation revert, fall back to
   `21000 + continuityRoots.length * 5000 + 20000`.
4. `consumer.execute(chainKey, headerNumber, txBytes, merkleProof,
   continuityProof, { gasLimit })`.

The worker is untrusted infrastructure: it only relays bytes. It cannot forge a
credit because every field the ledger acts on comes from a transaction the
precompile verified.

## Verified deployment

- `EnergyMeter`: `0x0d1b7c614e07B47153293469d356b6bA80978BF1` on Sepolia.
- `EvmV1Decoder`: `0xaDcDaBD5b96Af2c89829128321d913CF939d8604` on CC3.
- `EnergyCreditLedger`: `0x100FEb2D822CBb32C4e8f047D43615AC8851Ed79` on CC3.
- `EnergyProofConsumer`: `0x9e3743dEC51b82BD83d7fF7557650BF1C75ee096` on CC3.
- `CONSUMER_ROLE` was granted to `EnergyProofConsumer` in transaction
  `0x284e3f2059891c3be0d51af44aaecc68157d5176395a066ebbf8380e591e340`.

The demo settled 10 readings for 12,975 Wh. Replaying the first proof produced
`QueryAlreadyProcessed` in transaction
`0x9df20568f6787feac0a91d550782b96c27778df46912ee215b99e4d85133b302`; the
ledger balance and total stayed unchanged.

## Setup checklist

- [x] `.env` from `.env.example`; Sepolia RPC + funded key; CC3 testnet CTC.
- [x] Obtain and link the USC `EvmV1Decoder` library on CC3 Testnet.
- [x] Deploy `EnergyMeter` on Sepolia.
- [x] Deploy `EnergyCreditLedger` on CC3 Testnet.
- [x] Deploy `EnergyProofConsumer(sourceChainKey=1, energyMeter, ledger)` on CC3 Testnet.
- [x] Grant `CONSUMER_ROLE` to the deployed consumer and verify
  `ledger.hasRole(CONSUMER_ROLE, consumer)`.
- [x] Record all addresses in `deployments/README.md`.
