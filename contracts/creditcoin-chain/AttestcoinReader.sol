// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INativeQueryVerifierExpanded as INativeQueryVerifier} from "../interfaces/INativeQueryVerifier.sol";

/// @title AttestcoinReader
/// @notice Base contract for consuming Attestcoin transaction proofs.
/// @dev Child contracts validate and process the verified transaction in a hook.
abstract contract AttestcoinReader {
    /// @notice The query was already processed.
    error QueryAlreadyProcessed(bytes32 queryId);
    /// @notice The proof was rejected.
    error ProofVerificationFailed();

    /// @notice Emitted when a query is accepted.
    event QueryProcessed(bytes32 indexed queryId, uint64 indexed chainKey, uint64 blockHeight);

    /// @notice NativeQueryVerifier precompile.
    INativeQueryVerifier public constant VERIFIER = INativeQueryVerifier(0x0000000000000000000000000000000000000FD2);

    /// @notice Query processing status.
    mapping(bytes32 => bool) public processedQueries;

    /// @notice Verify and consume one source transaction proof.
    /// @param chainKey Attestcoin source-chain key.
    /// @param blockHeight Source-chain block height.
    /// @param encodedTransaction Encoded source transaction.
    /// @param merkleProof Transaction inclusion proof.
    /// @param continuityProof Chain continuity proof.
    /// @return accepted True if the transaction is consumed.
    /// @dev State changes are reverted if proof verification or the child hook fails.
    function execute(
        uint64 chainKey,
        uint64 blockHeight,
        bytes calldata encodedTransaction,
        INativeQueryVerifier.MerkleProof memory merkleProof,
        INativeQueryVerifier.ContinuityProof memory continuityProof
    ) external returns (bool) {
        bytes32 queryId = _computeQueryId(chainKey, blockHeight, merkleProof);
        require(!processedQueries[queryId], QueryAlreadyProcessed(queryId));

        bool verified = _verifyProof(chainKey, blockHeight, encodedTransaction, merkleProof, continuityProof);
        require(verified, ProofVerificationFailed());

        processedQueries[queryId] = true;
        emit QueryProcessed(queryId, chainKey, blockHeight);

        _onVerifiedTransaction(queryId, chainKey, blockHeight, encodedTransaction);
        return true;
    }

    /// @notice Verify a proof through the NativeQueryVerifier.
    /// @param chainKey Attestcoin source-chain key.
    /// @param blockHeight Source-chain block height.
    /// @param encodedTransaction Encoded source transaction.
    /// @param merkleProof Transaction inclusion proof.
    /// @param continuityProof Chain continuity proof.
    /// @return verified True if the proof is valid.
    /// @dev Production implementations call the fixed Creditcoin precompile.
    function _verifyProof(
        uint64 chainKey,
        uint64 blockHeight,
        bytes calldata encodedTransaction,
        INativeQueryVerifier.MerkleProof memory merkleProof,
        INativeQueryVerifier.ContinuityProof memory continuityProof
    ) internal virtual returns (bool) {
        return VERIFIER.verifyAndEmit({
            chainKey: chainKey,
            height: blockHeight,
            encodedTransaction: encodedTransaction,
            merkleProof: merkleProof,
            continuityProof: continuityProof
        });
    }

    /// @notice Derive the replay key for a source transaction.
    /// @param chainKey Attestcoin source-chain key.
    /// @param blockHeight Source-chain block height.
    /// @param merkleProof Transaction inclusion proof.
    /// @return queryId Deterministic replay key.
    /// @dev The key is based on source chain key, block height and transaction index.
    function _computeQueryId(uint64 chainKey, uint64 blockHeight, INativeQueryVerifier.MerkleProof memory merkleProof)
        internal
        view
        virtual
        returns (bytes32)
    {
        uint64 txIndex = VERIFIER.calculateTxIndex(merkleProof);

        return keccak256(abi.encodePacked(chainKey, blockHeight, txIndex));
    }

    /// @notice Handle a successfully verified transaction in the child contract.
    /// @param queryId Deterministic replay key.
    /// @param chainKey Attestcoin source-chain key.
    /// @param blockHeight Source-chain block height.
    /// @param encodedTransaction Encoded source transaction.
    function _onVerifiedTransaction(
        bytes32 queryId,
        uint64 chainKey,
        uint64 blockHeight,
        bytes memory encodedTransaction
    ) internal virtual;
}
