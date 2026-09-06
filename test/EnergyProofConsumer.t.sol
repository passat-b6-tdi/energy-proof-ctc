// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";
import {INativeQueryVerifier} from "@gluwa/usc-contracts/contracts/write-ability/INativeQueryVerifier.sol";
import {EnergyCreditLedger} from "../contracts/creditcoin-chain/EnergyCreditLedger.sol";
import {AttestcoinReader} from "../contracts/creditcoin-chain/AttestcoinReader.sol";
import {EnergyProofConsumer} from "../contracts/creditcoin-chain/EnergyProofConsumer.sol";
import {IEnergyCreditLedger} from "../contracts/interfaces/IEnergyCreditLedger.sol";
import {INativeQueryVerifierExpanded} from "../contracts/interfaces/INativeQueryVerifier.sol";

contract ConsumerHarness is EnergyProofConsumer {
    bool internal proofIsValid = true;
    bytes32 internal queryId = keccak256("query");

    constructor(address meter, address ledger) EnergyProofConsumer(1, meter, ledger) {}

    function setProofValidity(bool valid) external {
        proofIsValid = valid;
    }

    function setQueryId(bytes32 queryId_) external {
        queryId = queryId_;
    }

    function _verifyProof(
        uint64,
        uint64,
        bytes calldata,
        INativeQueryVerifierExpanded.MerkleProof memory,
        INativeQueryVerifierExpanded.ContinuityProof memory
    ) internal view override returns (bool) {
        return proofIsValid;
    }

    function _computeQueryId(uint64, uint64, INativeQueryVerifierExpanded.MerkleProof memory)
        internal
        view
        override
        returns (bytes32)
    {
        return queryId;
    }
}

contract EnergyProofConsumerTest is Test {
    EnergyCreditLedger internal ledger;
    ConsumerHarness internal consumer;

    address internal meter = makeAddr("meter");
    address internal producer = makeAddr("producer");
    bytes32 internal constant READING_ID = keccak256("reading");

    function setUp() public {
        ledger = new EnergyCreditLedger();
        consumer = new ConsumerHarness(meter, address(ledger));
        ledger.grantRole(ledger.CONSUMER_ROLE(), address(consumer));
    }

    function test_constructor_rejectsZeroMeter() public {
        vm.expectRevert(EnergyProofConsumer.ZeroEnergyMeter.selector);
        new ConsumerHarness(address(0), address(ledger));
    }

    function test_constructor_rejectsZeroLedger() public {
        vm.expectRevert(EnergyProofConsumer.ZeroLedger.selector);
        new ConsumerHarness(meter, address(0));
    }

    function _encodedTransaction(
        uint8 status,
        address emitter,
        bytes32 readingId,
        address eventProducer,
        uint32 wattHours
    ) internal pure returns (bytes memory) {
        return _encodedTransactionWithOptions(
            0, status, emitter, readingId, eventProducer, wattHours, 4, abi.encode(wattHours), 1
        );
    }

    function _encodedTransactionWithOptions(
        uint8 txType,
        uint8 status,
        address emitter,
        bytes32 readingId,
        address eventProducer,
        uint32 wattHours,
        uint256 topicCount,
        bytes memory data,
        uint256 logCount
    ) internal pure returns (bytes memory) {
        if (data.length == 0) data = abi.encode(wattHours);
        bytes32 signature = keccak256("EnergyProduced(address,address,bytes32,uint32)");
        bytes32[] memory topics = new bytes32[](topicCount);
        if (topicCount > 0) topics[0] = signature;
        if (topicCount > 1) topics[1] = bytes32(uint256(uint160(address(0x1234))));
        if (topicCount > 2) topics[2] = bytes32(uint256(uint160(eventProducer)));
        if (topicCount > 3) topics[3] = readingId;

        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](logCount);
        for (uint256 i = 0; i < logCount; ++i) {
            logs[i] = EvmV1Decoder.LogEntryTuple({address_: emitter, topics: topics, data: data});
        }

        bytes[] memory chunks = new bytes[](3);
        chunks[2] = abi.encode(status, uint64(50_000), logs, new bytes(0));
        return abi.encode(txType, chunks);
    }

    function _execute(bytes memory encoded) internal returns (bool) {
        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](0);
        INativeQueryVerifier.MerkleProof memory proof =
            INativeQueryVerifier.MerkleProof({root: bytes32(uint256(1)), siblings: siblings});
        INativeQueryVerifier.ContinuityProof memory continuity =
            INativeQueryVerifier.ContinuityProof({lowerEndpointDigest: bytes32(uint256(2)), roots: new bytes32[](0)});
        return consumer.execute(1, 123, encoded, proof, continuity);
    }

    function test_execute_validProofSettlesAndStoresProvenance() public {
        bool result = _execute(_encodedTransaction(1, meter, READING_ID, producer, 1_500));

        assertTrue(result);
        assertEq(ledger.balanceOf(producer), 1_500);
        assertTrue(ledger.settled(READING_ID));
        IEnergyCreditLedger.Settlement memory settlement = ledger.settlementOf(READING_ID);
        assertEq(settlement.producer, producer);
        assertEq(settlement.wattHours, 1_500);
        assertEq(settlement.sourceChainKey, 1);
        assertEq(settlement.sourceBlockHeight, 123);
    }

    function test_execute_invalidProofDoesNotChangeLedger() public {
        consumer.setProofValidity(false);
        vm.expectRevert(AttestcoinReader.ProofVerificationFailed.selector);
        _execute(_encodedTransaction(1, meter, READING_ID, producer, 1_500));

        assertEq(ledger.balanceOf(producer), 0);
        assertFalse(ledger.settled(READING_ID));
    }

    function test_execute_revertedSourceTxDoesNotSettle() public {
        vm.expectRevert(EnergyProofConsumer.SourceTransactionReverted.selector);
        _execute(_encodedTransaction(0, meter, READING_ID, producer, 1_500));

        assertEq(ledger.totalCredited(), 0);
    }

    function test_execute_wrongChainIsRejected() public {
        INativeQueryVerifier.MerkleProofEntry[] memory siblings = new INativeQueryVerifier.MerkleProofEntry[](0);
        INativeQueryVerifier.MerkleProof memory proof =
            INativeQueryVerifier.MerkleProof({root: bytes32(uint256(1)), siblings: siblings});
        INativeQueryVerifier.ContinuityProof memory continuity =
            INativeQueryVerifier.ContinuityProof({lowerEndpointDigest: bytes32(uint256(2)), roots: new bytes32[](0)});
        vm.expectRevert(abi.encodeWithSelector(EnergyProofConsumer.UnexpectedSourceChain.selector, 2));
        consumer.execute(2, 123, _encodedTransaction(1, meter, READING_ID, producer, 1), proof, continuity);
    }

    function test_execute_unsupportedTransactionTypeIsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyProofConsumer.UnsupportedTxType.selector, 5));
        _execute(_encodedTransactionWithOptions(5, 1, meter, READING_ID, producer, 1, 4, abi.encode(uint32(1)), 1));
    }

    function test_execute_withoutEnergyLogIsRejected() public {
        vm.expectRevert(EnergyProofConsumer.NoEnergyProducedLog.selector);
        _execute(_encodedTransactionWithOptions(0, 1, meter, READING_ID, producer, 1, 4, abi.encode(uint32(1)), 0));
    }

    function test_execute_multipleEnergyLogsIsRejected() public {
        vm.expectRevert(EnergyProofConsumer.MalformedLog.selector);
        _execute(_encodedTransactionWithOptions(0, 1, meter, READING_ID, producer, 1, 4, abi.encode(uint32(1)), 2));
    }

    function test_execute_malformedTopicsAreRejected() public {
        vm.expectRevert(EnergyProofConsumer.MalformedLog.selector);
        _execute(_encodedTransactionWithOptions(0, 1, meter, READING_ID, producer, 1, 3, abi.encode(uint32(1)), 1));
    }

    function test_execute_malformedDataIsRejected() public {
        vm.expectRevert(EnergyProofConsumer.MalformedLog.selector);
        _execute(_encodedTransactionWithOptions(0, 1, meter, READING_ID, producer, 1, 4, new bytes(31), 1));
    }

    function test_execute_zeroProducerIsRejected() public {
        vm.expectRevert(EnergyProofConsumer.ZeroProducer.selector);
        _execute(_encodedTransaction(1, meter, READING_ID, address(0), 1));
    }

    function test_execute_zeroWattHoursIsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyProofConsumer.WattHoursOutOfRange.selector, 0));
        _execute(_encodedTransaction(1, meter, READING_ID, producer, 0));
    }

    function test_execute_wattHoursAboveMaximumIsRejected() public {
        uint32 tooBig = uint32(consumer.MAX_WATT_HOURS() + 1);
        vm.expectRevert(abi.encodeWithSelector(EnergyProofConsumer.WattHoursOutOfRange.selector, tooBig));
        _execute(_encodedTransaction(1, meter, READING_ID, producer, tooBig));
    }

    function test_execute_replayReadingIdIsRejectedByLedger() public {
        _execute(_encodedTransaction(1, meter, READING_ID, producer, 1_500));
        consumer.setQueryId(keccak256("query-2"));
        vm.expectRevert(abi.encodeWithSelector(EnergyCreditLedger.ReadingAlreadySettled.selector, READING_ID));
        _execute(_encodedTransaction(1, meter, READING_ID, producer, 1_500));
    }

    function test_execute_failedHookRollsBackProcessedQuery() public {
        consumer.setProofValidity(false);
        vm.expectRevert(AttestcoinReader.ProofVerificationFailed.selector);
        _execute(_encodedTransaction(1, meter, READING_ID, producer, 1));

        consumer.setProofValidity(true);
        assertTrue(_execute(_encodedTransaction(1, meter, READING_ID, producer, 1)));
    }

    function test_execute_wrongEmitterDoesNotSettle() public {
        vm.expectRevert(abi.encodeWithSelector(EnergyProofConsumer.WrongEmitter.selector, address(0xbeef)));
        _execute(_encodedTransaction(1, address(0xbeef), READING_ID, producer, 1_500));

        assertEq(ledger.totalCredited(), 0);
    }

    function test_execute_replayIsRejected() public {
        _execute(_encodedTransaction(1, meter, READING_ID, producer, 1_500));

        vm.expectRevert(abi.encodeWithSelector(AttestcoinReader.QueryAlreadyProcessed.selector, keccak256("query")));
        _execute(_encodedTransaction(1, meter, keccak256("other"), producer, 1_500));
    }
}
