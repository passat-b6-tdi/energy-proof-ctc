// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AttestcoinReader} from "./AttestcoinReader.sol";
import {IEnergyCreditLedger} from "../interfaces/IEnergyCreditLedger.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";

contract EnergyProofConsumer is AttestcoinReader {
    error UnexpectedSourceChain(uint64 chainKey);
    error UnsupportedTxType(uint8 txType);
    error SourceTransactionReverted();
    error NoEnergyProducedLog();
    error WrongEmitter(address emitter);
    error MalformedLog();
    error ZeroProducer();
    error WattHoursOutOfRange(uint256 wattHours);

    bytes32 public constant ENERGY_PRODUCED_SIG = keccak256("EnergyProduced(address,bytes32,(uint32,address,bytes32))");
    uint256 public constant MAX_WATT_HOURS = 1_000_000_000;

    uint64 public immutable sourceChainKey;
    address public immutable energyMeter;
    IEnergyCreditLedger public immutable ledger;

    constructor(uint64 sourceChainKey_, address energyMeter_, address ledger_) {
        sourceChainKey = sourceChainKey_;
        energyMeter = energyMeter_;
        ledger = IEnergyCreditLedger(ledger_);
    }

    function _onVerifiedTransaction(bytes32 queryId, uint64 chainKey, bytes memory encodedTransaction)
        internal
        override
    {
        require(chainKey == sourceChainKey, UnexpectedSourceChain(chainKey));

        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        require(EvmV1Decoder.isValidTransactionType(txType), UnsupportedTxType(txType));

        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        require(receipt.receiptStatus == 1, SourceTransactionReverted());

        EvmV1Decoder.LogEntry[] memory logs = EvmV1Decoder.getLogsByEventSignature(receipt, ENERGY_PRODUCED_SIG);
        require(logs.length > 0, NoEnergyProducedLog());

        EvmV1Decoder.LogEntry memory log = logs[0];

        require(logs.address_ == energyMeter, WrongEmitter(log.address_));

        // EnergyProduced(address indexed oracle, bytes32 indexed readingId, EnergyParams params)
        // topics = [sig, oracle, readingId]
        // data = abi.encode(params)
        require(log.topics.length == 3 && log.topics[0] == ENERGY_PRODUCED_SIG, MalformedLog());
        require(log.data.length == 96, MalformedLog());

        (uint32 wattHours, address producer, bytes32 readingId) = abi.decode(log.data, (uint32, address, bytes32));

        require(producer != address(0), ZeroProducer());
        require(wattHours > 0 && wattHours <= MAX_WATT_HOURS, WattHoursOutOfRange(wattHours));

        ledger.credit(producer, wattHours, readingId, queryId);
    }
}
