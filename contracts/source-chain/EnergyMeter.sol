// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Register} from "./Register.sol";

/// @title EnergyMeter
/// @notice Records unique, bounded energy-production readings.
/// @dev Reading IDs are write-once and are also used for cross-chain replay protection.
/// @custom:security-contact See the repository security policy.
contract EnergyMeter is Register {
    /// @notice The reading identifier cannot be empty.
    error ZeroReadingId();
    /// @notice The credited producer cannot be the zero address.
    error ZeroProducer();
    /// @notice The reading is outside the accepted watt-hour range.
    error WrongWattHours(uint32 wattHours);
    /// @notice A reading identifier can only be recorded once.
    error ReadingIdAlreadyUsed(bytes32 readingId);

    /// @notice Emitted for each recorded production reading.
    event EnergyProduced(address indexed oracle, address indexed producer, bytes32 indexed readingId, uint32 wattHours);

    /// @notice Data stored for one reading.
    struct EnergyData {
        uint32 wattHours;
        address oracle;
        address producer;
        bytes32 readingId;
    }

    /// @notice Input for `recordProduction`.
    struct EnergyParams {
        uint32 wattHours;
        address producer;
        bytes32 readingId;
    }

    /// @notice Aggregate reading data for an account.
    struct UserData {
        uint256 totalWattHoursRecorded;
        bytes32[] readingIds;
    }

    /// @notice Upper bound on a single reading. 1e9 Wh = 1 GWh; fits in uint32.
    uint32 public constant MAX_WATT_HOURS = 1_000_000_000;

    /// @notice Reading ID to reading data.
    mapping(bytes32 readingId => EnergyData) public energyDatas;

    /// @notice Oracle totals and reading IDs.
    mapping(address oracle => UserData) internal _oracleDatas;

    /// @notice Producer totals and reading IDs.
    mapping(address producer => UserData) internal _producerDatas;

    /// @dev Deployer is bootstrapped as REGISTER + ORACLE so a single account is
    ///      immediately operational (DEFAULT_ADMIN is granted by `Register`).
    ///      Revoke in production if strict separation from block zero is wanted.
    constructor() {
        _grantRole(REGISTER_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
    }

    /// @notice Record one production reading.
    /// @param energyParams Reading data.
    /// @dev Only an account with `ORACLE_ROLE` can submit a reading.
    function recordProduction(EnergyParams memory energyParams) external onlyRole(ORACLE_ROLE) {
        _recordProduction(energyParams);
    }

    /// @notice Return an oracle's total energy.
    /// @param oracle Oracle account.
    /// @return total Total watt-hours recorded by the oracle.
    function oracleTotal(address oracle) external view returns (uint256) {
        return _oracleDatas[oracle].totalWattHoursRecorded;
    }

    /// @notice Return an oracle's reading IDs.
    /// @param oracle Oracle account.
    /// @return readingIds Reading IDs recorded by the oracle.
    function oracleReadingIds(address oracle) external view returns (bytes32[] memory) {
        return _oracleDatas[oracle].readingIds;
    }

    /// @notice Return a producer's total energy.
    /// @param producer Producer account.
    /// @return total Total watt-hours attributed to the producer.
    function producerTotal(address producer) external view returns (uint256) {
        return _producerDatas[producer].totalWattHoursRecorded;
    }

    /// @notice Return a producer's reading IDs.
    /// @param producer Producer account.
    /// @return readingIds Reading IDs attributed to the producer.
    function producerReadingIds(address producer) external view returns (bytes32[] memory) {
        return _producerDatas[producer].readingIds;
    }

    /// @param energyParams Reading to validate and store.
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

    /// @param userData Aggregate data to update.
    /// @param energyParams Reading whose value and ID are appended.
    function _setUserData(UserData storage userData, EnergyParams memory energyParams) internal {
        userData.totalWattHoursRecorded += energyParams.wattHours;
        userData.readingIds.push(energyParams.readingId);
    }
}
