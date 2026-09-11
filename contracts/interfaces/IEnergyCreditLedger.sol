// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IEnergyCreditLedger
/// @notice Interface for the Creditcoin energy ledger.
/// @dev Implementations should preserve the one-settlement-per-reading rule.
/// @custom:security-contact See the repository security policy.
interface IEnergyCreditLedger {
    /// @notice Audit record for one settled reading.
    struct Settlement {
        address producer;
        uint256 wattHours;
        bytes32 queryId;
        uint64 sourceChainKey;
        uint64 sourceBlockHeight;
    }

    /// @notice Record one verified energy reading.
    /// @param producer Address credited from the source event.
    /// @param wattHours Energy produced, in watt-hours.
    /// @param readingId Source reading ID and settlement key.
    /// @param queryId Attestcoin query ID used for verification.
    /// @param sourceChainKey Attestcoin source-chain key.
    /// @param sourceBlockHeight Source-chain block height.
    function credit(
        address producer,
        uint256 wattHours,
        bytes32 readingId,
        bytes32 queryId,
        uint64 sourceChainKey,
        uint64 sourceBlockHeight
    ) external;

    /// @notice Return a producer's cumulative settled energy.
    /// @param producer Producer account.
    /// @return wattHours Total settled watt-hours.
    function balanceOf(address producer) external view returns (uint256);

    /// @notice Return whether a source reading has already been settled.
    /// @param readingId Source reading ID.
    /// @return isSettled True if settled.
    function settled(bytes32 readingId) external view returns (bool);

    /// @notice Return the audit record for a source reading.
    /// @param readingId Source reading ID.
    /// @return settlement Stored settlement data.
    function settlementOf(bytes32 readingId) external view returns (Settlement memory);
}
