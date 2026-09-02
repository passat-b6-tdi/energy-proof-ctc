// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IEnergyCreditLedger} from "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract Register is AccessControl {
    bytes32 public constant REGISTER_ROLE = keccak256("REGISTER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function grantRegisterRole(address register) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(REGISTER_ROLE, register);
    }

    function addOracle(address oracle) external onlyRole(REGISTER_ROLE) {
        _grantRole(ORACLE_ROLE, oracle);
    }
}
