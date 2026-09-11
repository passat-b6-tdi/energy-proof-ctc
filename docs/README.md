# EnergyProof CTC

EnergyProof turns an energy reading on Ethereum Sepolia into a verified energy
credit on Creditcoin. Attestcoin verifies the source transaction before the
Creditcoin ledger changes state.

The live prototype settled 10 readings from 3 producers for `12,975 Wh` and
rejected a replay with `QueryAlreadyProcessed`.

Start with [How it works](architecture.md), then read the
[Attestcoin integration](attestcoin-integration.md) and
[Security invariants](security-invariants.md).
