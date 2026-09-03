// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INativeQueryVerifierExpanded as INativeQueryVerifier} from "../interfaces/INativeQueryVerifier.sol";

abstract contract AttestcoinReader {
    error QueryAlreadyProcessed(bytes32 queryId);
    error ProofVerificationFailed();

    event QueryProcessed(bytes32 indexed queryId, uint64 indexed chainKey, uint64 blockHeight);

    INativeQueryVerifier public constant VERIFIER = INativeQueryVerifier(0x0000000000000000000000000000000000000FD2);

    mapping(bytes32 => bool) public processedQueries;

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

    function _computeQueryId(uint64 chainKey, uint64 blockHeight, INativeQueryVerifier.MerkleProof memory merkleProof)
        internal
        view
        virtual
        returns (bytes32)
    {
        uint64 txIndex = VERIFIER.calculateTxIndex(merkleProof);

        return keccak256(abi.encodePacked(chainKey, blockHeight, txIndex));
    }

    function _onVerifiedTransaction(
        bytes32 queryId,
        uint64 chainKey,
        uint64 blockHeight,
        bytes memory encodedTransaction
    ) internal virtual;
}
