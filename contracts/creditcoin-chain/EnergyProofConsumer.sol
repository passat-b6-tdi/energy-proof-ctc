// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AttestcoinReader} from "./AttestcoinReader.sol";
import {IEnergyCreditLedger} from "../interfaces/IEnergyCreditLedger.sol";
import {EvmV1Decoder} from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";

/// @title EnergyProofConsumer
/// @notice Validates verified energy events and credits them on Creditcoin.
/// @dev Accepts one matching `EnergyProduced` log per source transaction.
/// @custom:security-contact See the repository security policy.
contract EnergyProofConsumer is AttestcoinReader {
    /// @notice The proof used the wrong source chain.
    error UnexpectedSourceChain(uint64 chainKey);
    /// @notice The transaction type is unsupported.
    error UnsupportedTxType(uint8 txType);
    /// @notice The source transaction reverted.
    error SourceTransactionReverted();
    /// @notice No EnergyProduced event was found.
    error NoEnergyProducedLog();
    /// @notice The event has the wrong emitter.
    error WrongEmitter(address emitter);
    /// @notice The event has an invalid layout.
    error MalformedLog();
    /// @notice The producer is the zero address.
    error ZeroProducer();
    /// @notice The watt-hour value is invalid.
    error WattHoursOutOfRange(uint256 wattHours);
    /// @notice The meter address is zero.
    error ZeroEnergyMeter();
    /// @notice The ledger address is zero.
    error ZeroLedger();

    /// @notice EnergyProduced event signature.
    /// @dev Must match the event emitted by `EnergyMeter`.
    bytes32 public constant ENERGY_PRODUCED_SIG = keccak256("EnergyProduced(address,address,bytes32,uint32)");

    /// @notice Maximum watt-hours per event.
    uint256 public constant MAX_WATT_HOURS = 1_000_000_000;

    /// @notice Accepted Attestcoin source-chain key.
    uint64 public immutable sourceChainKey;

    /// @notice Trusted EnergyMeter address.
    address public immutable energyMeter;

    /// @notice Destination ledger address.
    IEnergyCreditLedger public immutable ledger;

    /// @param sourceChainKey_ Attestcoin source key, not the EVM chain ID.
    /// @param energyMeter_ Trusted source-chain EnergyMeter address.
    /// @param ledger_ Destination EnergyCreditLedger address.
    /// @dev Both contract addresses are immutable after deployment.
    constructor(uint64 sourceChainKey_, address energyMeter_, address ledger_) {
        require(energyMeter_ != address(0), ZeroEnergyMeter());
        require(ledger_ != address(0), ZeroLedger());
        sourceChainKey = sourceChainKey_;
        energyMeter = energyMeter_;
        ledger = IEnergyCreditLedger(ledger_);
    }

    /// @inheritdoc AttestcoinReader
    /// @dev Requires exactly one matching event.
    /// @param queryId Deterministic replay key.
    /// @param chainKey Attestcoin source-chain key.
    /// @param blockHeight Source-chain block height.
    /// @param encodedTransaction Encoded source transaction.
    function _onVerifiedTransaction(
        bytes32 queryId,
        uint64 chainKey,
        uint64 blockHeight,
        bytes memory encodedTransaction
    ) internal override {
        require(chainKey == sourceChainKey, UnexpectedSourceChain(chainKey));

        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        require(EvmV1Decoder.isValidTransactionType(txType), UnsupportedTxType(txType));

        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        require(receipt.receiptStatus == 1, SourceTransactionReverted());

        EvmV1Decoder.LogEntry[] memory logs = EvmV1Decoder.getLogsByEventSignature(receipt, ENERGY_PRODUCED_SIG);
        require(logs.length > 0, NoEnergyProducedLog());
        require(logs.length == 1, MalformedLog());

        // MVP: one reading per source transaction, so the first matching log is authoritative.
        EvmV1Decoder.LogEntry memory log = logs[0];

        require(log.address_ == energyMeter, WrongEmitter(log.address_));

        // EnergyProduced(address indexed oracle, address indexed producer,
        //                bytes32 indexed readingId, uint32 wattHours)
        // topics = [sig, oracle, producer, readingId]; data = abi.encode(wattHours).
        require(log.topics.length == 4 && log.topics[0] == ENERGY_PRODUCED_SIG, MalformedLog());
        require(log.data.length == 32, MalformedLog());

        address producer = address(uint160(uint256(log.topics[2])));
        bytes32 readingId = log.topics[3];
        uint32 wattHours = abi.decode(log.data, (uint32));

        require(producer != address(0), ZeroProducer());
        require(wattHours > 0 && wattHours <= MAX_WATT_HOURS, WattHoursOutOfRange(wattHours));

        ledger.credit(producer, wattHours, readingId, queryId, chainKey, blockHeight);
    }
}
