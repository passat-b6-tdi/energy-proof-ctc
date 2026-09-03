// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IEnergyCreditLedger} from "../interfaces/IEnergyCreditLedger.sol";

contract EnergyCreditLedger is IEnergyCreditLedger, AccessControl {
    bytes32 public constant CONSUMER_ROLE = keccak256("CONSUMER_ROLE");

    mapping(address => uint256) public balanceOf;

    mapping(bytes32 => bool) public settled;

    uint256 public totalCredited;

    event ConsumerInitialized(address indexed consumer);
    event SettlementRecorded(
        address indexed producer,
        uint256 wattHours,
        bytes32 indexed readingId,
        bytes32 indexed queryId,
        uint256 newBalance
    );

    error ZeroProducer();
    error ReadingAlreadySettled(bytes32 readingId);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function credit(address producer, uint256 wattHours, bytes32 readingId, bytes32 queryId)
        external
        onlyRole(CONSUMER_ROLE)
    {
        require(producer != address(0), ZeroProducer());
        require(!settled[readingId], ReadingAlreadySettled(readingId));

        uint256 newBalance = balanceOf[producer] + wattHours;

        balanceOf[producer] = newBalance;
        settled[readingId] = true;
        totalCredited += wattHours;

        emit SettlementRecorded(producer, wattHours, readingId, queryId, newBalance);
    }
}
