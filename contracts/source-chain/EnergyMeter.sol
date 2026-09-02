// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Register} from "./Register.sol";

contract EnergyMeter is Register {
    error ZeroReadingId();
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

    mapping(bytes32 readingId => EnergyData) public energyDatas;

    mapping(address oracle => OracleData) internal _oracleDatas;

    constructor() {
        _grantRole(REGISTER_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
    }

    function recordProduction(uint32 wattHours, bytes32 readingId) external onlyRole(ORACLE_ROLE) {
        require(readingId != bytes32(0), ZeroReadingId());
        require(wattHours > 0 && wattHours <= MAX_WATT_HOURS, WrongWattHours(wattHours));

        EnergyData storage energyData = energyDatas[readingId];
        require(energyData.readingId == bytes32(0), ReadingIdAlreadyUsed(readingId));
        energyData = EnergyData({wattHours: wattHours, oracle: msg.sender, readingId: readingId});

        OracleData storage oracleData = _oracleDatas[msg.sender];
        oracleData.totalWattHoursRecorded += wattHours;
        oracleData.readingIds.push(readingId);

        emit EnergyProduced(msg.sender, wattHours, readingId);
    }

    function oracleTotal(address oracle) external view returns (uint256) {
        return _oracleDatas[oracle].totalWattHoursRecorded;
    }

    function oracleReadingIds(address oracle) external view returns (bytes32[] memory) {
        return _oracleDatas[oracle].readingIds;
    }
}
