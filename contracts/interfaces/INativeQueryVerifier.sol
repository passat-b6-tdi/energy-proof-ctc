// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INativeQueryVerifier} from "@gluwa/usc-contracts/contracts/write-ability/INativeQueryVerifier.sol";

/// @title INativeQueryVerifierExpanded
/// @notice Interface for Creditcoin's Attestcoin readability precompile.
/// @dev This interface declares ABI only; verification is implemented by Creditcoin.
/// @custom:security-contact See the repository security policy.
interface INativeQueryVerifierExpanded is INativeQueryVerifier {
    /// @notice Verify source transaction inclusion and chain continuity.
    /// @param chainKey Attestcoin source-chain key.
    /// @param height Source-chain block height.
    /// @param encodedTransaction Encoded source transaction.
    /// @param merkleProof Transaction inclusion proof.
    /// @param continuityProof Chain continuity proof.
    /// @return verified True if the inclusion and continuity proofs verify.
    function verifyAndEmit(
        uint64 chainKey,
        uint64 height,
        bytes calldata encodedTransaction,
        INativeQueryVerifier.MerkleProof calldata merkleProof,
        INativeQueryVerifier.ContinuityProof calldata continuityProof
    ) external returns (bool);

    /// @notice Return the transaction index from a Merkle proof.
    /// @param merkleProof Transaction inclusion proof.
    /// @return transactionIndex Index of the transaction in its source block.
    function calculateTxIndex(INativeQueryVerifier.MerkleProof calldata merkleProof) external view returns (uint64);
}
