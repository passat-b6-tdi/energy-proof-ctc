// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IEnergyCreditLedger {
    function credit(address producer, uint256 wattHours, bytes32 readingId, bytes32 queryId) external;

    function balanceOf(address producer) external view returns (uint256);

    function settled(bytes32 readingId) external view returns (bool);
}
