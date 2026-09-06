// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title Register
/// @notice Access registry for registrars and metering oracles.
/// @dev The default admin manages registrars, and registrars manage oracles.
abstract contract Register is AccessControl {
    bytes32 public constant REGISTER_ROLE = keccak256("REGISTER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(REGISTER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ORACLE_ROLE, REGISTER_ROLE);
    }

    /// @notice Grant registrar permissions.
    /// @param register Account to authorize.
    function grantRegisterRole(address register) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(REGISTER_ROLE, register);
    }

    /// @notice Grant oracle permissions.
    /// @param oracle Account to authorize.
    function addOracle(address oracle) external onlyRole(REGISTER_ROLE) {
        _grantRole(ORACLE_ROLE, oracle);
    }

    /// @notice Revoke registrar permissions.
    /// @param register Account to revoke.
    function removeRegisterRole(address register) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(REGISTER_ROLE, register);
    }

    /// @notice Revoke oracle permissions.
    /// @param oracle Account to revoke.
    function removeOracle(address oracle) external onlyRole(REGISTER_ROLE) {
        _revokeRole(ORACLE_ROLE, oracle);
    }
}
