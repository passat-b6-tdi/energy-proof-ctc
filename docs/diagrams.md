# Diagrams

Mermaid source. Renders on GitHub, in Obsidian, and in most Markdown tools.
A rendered, theme-aware version for the deck lives in the project Artifact.

---

## 1. Components and data flow

What crosses the chain boundary, and who talks to whom.

```mermaid
flowchart LR
    subgraph SEP["Ethereum Sepolia -- source chain (key 1)"]
        P([Oracle]) -->|"recordProduction(EnergyParams)"| EM["EnergyMeter"]
        EM -->|emit| LOG(["EnergyProduced log"])
    end

    subgraph OFF["Off-chain (untrusted relay)"]
        W["worker/watch.ts"]
    end

    ATT["Attestor network<br/>quorum -&gt; attestation chain"]
    PB["Attestcoin proof builder<br/>prover.cc3-testnet..."]

    subgraph CC["Creditcoin CC3 Testnet -- 102031"]
        EPC["EnergyProofConsumer<br/>(is AttestcoinReader)"]
        PC[["NativeQueryVerifier<br/>precompile 0x...0FD2"]]
        ECL["EnergyCreditLedger"]
    end

    LOG -.->|queryFilter poll| W
    SEP ==>|blocks watched| ATT
    ATT -->|attested heights| PB
    W -->|"getProof(txHash)"| PB
    PB -->|merkle + continuity proof| W
    W -->|"execute(chainKey, blockHeight, encodedTransaction, merkleProof, continuityProof)"| EPC
    EPC -->|"verifyAndEmit(...)"| PC
    PC -->|true / false| EPC
    EPC -->|"credit(producer, wattHours, readingId, queryId, sourceChainKey, sourceBlockHeight)"| ECL
    ECL -.->|emit SettlementRecorded| W
```

The worker only relays bytes. Every field the ledger acts on comes from a
transaction the precompile verified as included in an attested Sepolia block.

---

## 2. Happy path (sequence)

```mermaid
sequenceDiagram
    actor P as Producer
    participant EM as EnergyMeter (Sepolia)
    participant W as worker/watch.ts
    participant PB as Proof builder
    participant V as NativeQueryVerifier 0x...0FD2
    participant C as EnergyProofConsumer
    participant L as EnergyCreditLedger

    P->>EM: recordProduction(EnergyParams)
    EM-->>W: EnergyProduced(oracle, producer, readingId, wattHours)
    W->>PB: waitUntilHeightAttested(chainKey=1, block)
    Note over W,PB: ~8 min until the Sepolia block is attested
    W->>PB: getProof(txHash)
    PB-->>W: { txBytes, merkleProof, continuityProof }
    W->>C: execute(chainKey, height, txBytes, merkleProof, continuityProof)
    C->>C: queryId = keccak(chainKey, height, txIndex)
    C->>C: revert if processedQueries[queryId]
    C->>V: verifyAndEmit(chainKey, height, txBytes, merkleProof, continuityProof)
    V-->>C: true
    C->>C: decode receipt; status==1; find EnergyProduced log; emitter==EnergyMeter; bounds
    C->>L: credit(producer, wattHours, readingId, queryId, chainKey, blockHeight)
    L->>L: revert if settled[readingId]
    L-->>W: SettlementRecorded(producer, wattHours, readingId, queryId, newBalance)
```

---

## 3. The verification gate (consumer validation)

Every check and the revert it raises. Left column is the pass-through path.

```mermaid
flowchart TD
    A["execute(chainKey, blockHeight, encodedTransaction, merkleProof, continuityProof)"] --> B{"processedQueries[queryId] ?"}
    B -->|yes| R1[["revert QueryAlreadyProcessed"]]
    B -->|no| C{"verifyAndEmit(...) == true ?"}
    C -->|no| R2[["revert ProofVerificationFailed"]]
    C -->|yes| D["mark processed; emit QueryProcessed"]
    D --> E{"chainKey == sourceChainKey ?"}
    E -->|no| R3[["revert UnexpectedSourceChain"]]
    E -->|yes| F{"valid tx type ?"}
    F -->|no| R4[["revert (unsupported tx type)"]]
    F -->|yes| G{"receiptStatus == 1 ?"}
    G -->|no| R5[["revert SourceTransactionReverted"]]
    G -->|yes| H{"EnergyProduced log present ?"}
    H -->|no| R6[["revert NoEnergyProducedLog"]]
    H -->|yes| I{"log.address_ == energyMeter ?"}
    I -->|no| R7[["revert WrongEmitter"]]
    I -->|yes| J{"topics/data shape ok ?"}
    J -->|no| R8[["revert MalformedLog"]]
    J -->|yes| K{"0 &lt; wattHours &lt;= MAX ?"}
    K -->|no| R9[["revert WattHoursOutOfRange"]]
    K -->|yes| L{"settled[readingId] ?"}
    L -->|yes| R10[["revert ReadingAlreadySettled"]]
    L -->|no| M{"producer != address(0) ?"}
    M -->|no| R11[["revert ZeroProducer"]]
    M -->|yes| S["settled = true<br/>balanceOf += wattHours<br/>totalCredited += wattHours<br/>emit SettlementRecorded"]
```

---

## 4. Lifecycle of one reading

```mermaid
stateDiagram-v2
    [*] --> Emitted: recordProduction(EnergyParams) on Sepolia
    Emitted --> AwaitingAttestation: worker sees log
    AwaitingAttestation --> Attested: quorum reached (~8 min)
    Attested --> ProofBuilt: proofBuilder.getProof
    ProofBuilt --> Submitted: worker calls execute()
    Submitted --> Verified: precompile returns true
    Submitted --> Rejected: precompile returns false
    Verified --> Settled: ledger.credit succeeds
    Verified --> Rejected: validation or replay check fails
    Settled --> [*]
    Rejected --> [*]
```

---

## 5. Deploy order

The two Creditcoin contracts need each other's address, so the ledger takes its
consumer in a one-shot call after both are deployed.

```mermaid
flowchart TD
    D1["1 - deploy EvmV1Decoder library (CC3 Testnet)"] --> D2["2 - deploy EnergyMeter (Sepolia)"]
    D2 --> D3["3 - deploy EnergyCreditLedger (CC3, no ctor args)"]
    D3 --> D4["4 - deploy EnergyProofConsumer(chainKey=1, energyMeter, ledger)<br/>linked against EvmV1Decoder"]
    D4 --> D5["5 - ledger.grantRole(CONSUMER_ROLE, consumer)  // single authorization model"]
    D5 --> D6["record addresses in deployments/README.md and .env"]
```
