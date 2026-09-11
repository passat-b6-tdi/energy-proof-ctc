# Security invariants

Each invariant maps to at least one test. All listed invariants have automated
coverage; the live replay transaction is recorded in `deployments/README.md`.

## Verification gate

- **I1** No `EnergyCreditLedger` state change unless `VERIFIER.verifyAndEmit`
  returned `true` for the submitted proof. ✅ `test_execute_invalidProofDoesNotChangeLedger`
- **I2** A source transaction whose receipt status is not `1` settles nothing.
  ✅ `test_execute_revertedSourceTxDoesNotSettle`
- **I3** A verified transaction with no `EnergyProduced` log settles nothing.
  ✅ `test_execute_withoutEnergyLogIsRejected`
- **I4** A log with the right signature but emitted by an address other than the
  configured `energyMeter` settles nothing. ✅ `test_execute_wrongEmitterDoesNotSettle`
- **I5** `chainKey != sourceChainKey` reverts even if the proof verifies.
  ✅ `test_execute_wrongChainIsRejected`
- **I6** Malformed log shape (topics length, data length) reverts. ✅ `test_execute_malformedTopicsAreRejected`, `test_execute_malformedDataIsRejected`
- **I7** `wattHours == 0` or `wattHours > MAX_WATT_HOURS` reverts. ✅ `test_execute_zeroWattHoursIsRejected`, `test_execute_wattHoursAboveMaximumIsRejected`

## Replay

- **I8** The same proof submitted twice: second call reverts
  `QueryAlreadyProcessed`, ledger unchanged. ✅ `test_execute_replayIsRejected` and live replay transaction
- **I9** Two distinct proofs carrying the same `readingId`: second reverts
  `ReadingAlreadySettled`. ✅ `EnergyCreditLedgerTest.test_credit_rejectsReplayOfReadingId`
- **I10** `EnergyMeter` rejects a reused `readingId` at emission. ✅
  `EnergyMeterTest.test_recordProduction_revertsOnReusedReadingId`

## Access control

- **I11** `EnergyCreditLedger.credit` reverts for any caller without
  `CONSUMER_ROLE`. ✅ `test_credit_onlyConsumer`
- **I12** Only an account with `DEFAULT_ADMIN_ROLE` can grant `CONSUMER_ROLE`; a
  caller without that role cannot write to the ledger. ✅
  `test_onlyAdminCanGrantConsumerRole`
- **I13** `credit(address(0), ...)` reverts. ✅ `test_credit_rejectsZeroProducer`

## Value integrity

- **I14** `balanceOf[producer]` increases by exactly `wattHours`; `totalCredited`
  tracks the sum. ✅ `test_credit_happyPath`, `test_credit_accumulatesAcrossReadings`
- **I15** Event signature constant in `EnergyProofConsumer` equals
  `keccak256("EnergyProduced(address,address,bytes32,uint32)")`. ✅
  `EnergyMeterTest.test_eventSignatureMatchesConsumerConstant`

## Griefing (accepted, non-issues)

- Anyone may call `execute` with someone else's valid proof. Effect: the rightful
  producer is credited, the caller pays gas. No mitigation needed.
- `EnergyMeter.recordProduction` is restricted to `ORACLE_ROLE`. A recorded
  reading still has to be attested and proven before it can settle.
