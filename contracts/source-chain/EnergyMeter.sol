// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Register} from "./Register.sol";

contract EnergyMeter is Register {
    error WrongWattHours(uint32 wattHours);
    error ReadingIdAlreadyUsed(bytes32 readingId);

    event EnergyProduced(address indexed oracle, uint32 wattHours, bytes32 indexed readingId);

    struct EnergyData {
        uint32 wattHours;
        address oracle;
        bytes32 readingId;
    }

    struct OracleData {
        uint256 totalWattHoursRecorded;
        bytes32[] readingIds;
    }

    // 1e9 Wh = 1 GWh
    uint32 public constant MAX_WATT_HOURS = 1_000_000_000;

    mapping(bytes32 readingId => EnergyData energyData) public energyDatas;
    mapping(address oracle => OracleData oracleData) public oracleDatas;

    function recordProduction(uint32 wattHours, bytes32 readingId) external onlyRole(ORACLE_ROLE) {
        require(wattHours > 0 && wattHours <= MAX_WATT_HOURS, WrongWattHours(wattHours));

        EnergyData storage energyData = energyDatas[readingId];
        require(energyData.readingId == bytes32(0), ReadingIdAlreadyUsed(readingId));

        OracleData storage oracleData = oracleDatas[msg.sender];

        energyData = EnergyData(wattHours, msg.sender, readingId);

        oracleData.totalWattHoursRecorded += wattHours;
        oracleData.readingIds.push(readingId);

        emit EnergyProduced(msg.sender, wattHours, readingId);
    }
}
