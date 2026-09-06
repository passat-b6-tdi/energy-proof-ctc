// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IEnergyCreditLedger} from "../interfaces/IEnergyCreditLedger.sol";

/// @title EnergyCreditLedger
/// @notice Creditcoin ledger for energy credits created by verified source
///         readings.
/// @dev The deployer grants `CONSUMER_ROLE` to the deployed consumer. This role
///      is the only write authorization; each reading ID is settled once.
contract EnergyCreditLedger is IEnergyCreditLedger, AccessControl {
    /// @notice A settlement cannot credit the zero address.
    error ZeroProducer();
    /// @notice A settlement must identify a source reading.
    error ZeroReadingId();
    /// @notice A source reading cannot be settled twice.
    error ReadingAlreadySettled(bytes32 readingId);
    /// @notice A settlement must retain its proof query identifier.
    error ZeroQueryId();
    /// @notice A settlement must credit a positive amount.
    error ZeroWattHours();

    /// @notice Emitted after a verified reading increases a producer balance.
    event SettlementRecorded(
        address indexed producer,
        uint256 wattHours,
        bytes32 indexed readingId,
        bytes32 indexed queryId,
        uint256 newBalance
    );

    bytes32 public constant CONSUMER_ROLE = keccak256("CONSUMER_ROLE");

    /// @inheritdoc IEnergyCreditLedger
    mapping(address => uint256) public balanceOf;
    /// @notice Sum of all settled watt-hours across producers.
    uint256 public totalCredited;

    mapping(bytes32 => Settlement) private _settlements;

    /// @notice Grant the deployer the admin role used to wire the consumer.
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc IEnergyCreditLedger
    function credit(
        address producer,
        uint256 wattHours,
        bytes32 readingId,
        bytes32 queryId,
        uint64 sourceChainKey,
        uint64 sourceBlockHeight
    ) external onlyRole(CONSUMER_ROLE) {
        require(producer != address(0), ZeroProducer());
        require(readingId != bytes32(0), ZeroReadingId());
        require(!settled(readingId), ReadingAlreadySettled(readingId));

        uint256 newBalance = balanceOf[producer] + wattHours;

        balanceOf[producer] = newBalance;
        totalCredited += wattHours;
        _settlements[readingId] = Settlement({
            producer: producer,
            wattHours: wattHours,
            queryId: queryId,
            sourceChainKey: sourceChainKey,
            sourceBlockHeight: sourceBlockHeight
        });

        emit SettlementRecorded(producer, wattHours, readingId, queryId, newBalance);
    }

    /// @inheritdoc IEnergyCreditLedger
    function settlementOf(bytes32 readingId) external view returns (Settlement memory) {
        return _settlements[readingId];
    }

    /// @inheritdoc IEnergyCreditLedger
    function settled(bytes32 readingId) public view returns (bool) {
        return _settlements[readingId].producer != address(0);
    }
}
