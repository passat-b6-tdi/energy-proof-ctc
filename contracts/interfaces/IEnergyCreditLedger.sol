// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IEnergyCreditLedger {
    struct Settlement {
        address producer;
        uint256 wattHours;
        bytes32 queryId;
        uint64 sourceChainKey;
        uint64 sourceBlockHeight;
    }

    function credit(
        address producer,
        uint256 wattHours,
        bytes32 readingId,
        bytes32 queryId,
        uint64 sourceChainKey,
        uint64 sourceBlockHeight
    ) external;

    function balanceOf(address producer) external view returns (uint256);

    function settled(bytes32 readingId) external view returns (bool);

    function settlementOf(bytes32 readingId) external view returns (Settlement memory);
}
