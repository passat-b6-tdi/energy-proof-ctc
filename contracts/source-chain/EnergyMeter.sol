// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Register} from "./Register.sol";

contract EnergyMeter is Register {
    error ZeroReadingId();
    error ZeroProducer();
    error WrongWattHours(uint32 wattHours);
    error ReadingIdAlreadyUsed(bytes32 readingId);

    event EnergyProduced(address indexed oracle, address indexed producer, bytes32 indexed readingId, uint32 wattHours);

    struct EnergyData {
        uint32 wattHours;
        address oracle;
        address producer;
        bytes32 readingId;
    }

    struct EnergyParams {
        uint32 wattHours;
        address producer;
        bytes32 readingId;
    }

    struct UserData {
        uint256 totalWattHoursRecorded;
        bytes32[] readingIds;
    }


    uint32 public constant MAX_WATT_HOURS = 1_000_000_000;

    mapping(bytes32 readingId => EnergyData) public energyDatas;

    mapping(address oracle => UserData) internal _oracleDatas;

    mapping(address producer => UserData) internal _producerDatas;

    constructor() {
        _grantRole(REGISTER_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
    }

    function recordProduction(EnergyParams memory energyParams) external onlyRole(ORACLE_ROLE) {
        _recordProduction(energyParams);
    }

    function oracleTotal(address oracle) external view returns (uint256) {
        return _oracleDatas[oracle].totalWattHoursRecorded;
    }

    function oracleReadingIds(address oracle) external view returns (bytes32[] memory) {
        return _oracleDatas[oracle].readingIds;
    }

    function producerTotal(address producer) external view returns (uint256) {
        return _producerDatas[producer].totalWattHoursProduced;
    }

    function producerReadingIds(address producer) external view returns (bytes32[] memory) {
        return _producerDatas[producer].readingIds;
    }

    function _recordProduction(EnergyParams memory energyParams) internal {
        require(energyParams.readingId != bytes32(0), ZeroReadingId());
        require(energyParams.producer != address(0), ZeroProducer());
        require(
            energyParams.wattHours > 0 && energyParams.wattHours <= MAX_WATT_HOURS,
            WrongWattHours(energyParams.wattHours)
        );

        EnergyData storage energyDataStorage = energyDatas[energyParams.readingId];
        require(energyDataStorage.oracle == address(0), ReadingIdAlreadyUsed(energyParams.readingId));
        energyDataStorage.wattHours = energyParams.wattHours;
        energyDataStorage.oracle = msg.sender;
        energyDataStorage.producer = energyParams.producer;
        energyDataStorage.readingId = energyParams.readingId;

        _setUserData(_oracleDatas[msg.sender], energyParams);
        _setUserData(_producerDatas[energyParams.producer], energyParams);

        emit EnergyProduced(msg.sender, energyParams.producer, energyParams.readingId, energyParams.wattHours);
    }

    function _setUserData(UserData storage userData, EnergyParams memory energyParams) internal {
        userData.totalWattHoursRecorded += energyParams.wattHours;
        userData.readingIds.push(energyParams.readingId);
    }
}
