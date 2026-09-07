#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
    echo "Missing .env. Copy .env.example to .env and fill the deployment values." >&2
    exit 1
fi

set -a
source .env
set +a

: "${CREDITCOIN_RPC_URL:?CREDITCOIN_RPC_URL is required}"
: "${DEPLOYER_ACCOUNT:?DEPLOYER_ACCOUNT is required}"
: "${EVM_V1_DECODER_ADDRESS:?EVM_V1_DECODER_ADDRESS is required}"
: "${ENERGY_METER_ADDRESS:?ENERGY_METER_ADDRESS is required}"

VERIFY_FLAGS=(
    --verifier blockscout
    --verifier-url "${CREDITCOIN_VERIFIER_URL:-https://creditcoin-testnet.blockscout.com/api/}"
)

decoder="$EVM_V1_DECODER_ADDRESS"
export DAPP_LIBRARIES="node_modules/@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol:EvmV1Decoder:$decoder"

if [[ -n "${ENERGY_CREDIT_LEDGER_ADDRESS:-}" ]]; then
    ledger="$ENERGY_CREDIT_LEDGER_ADDRESS"
    echo "Using existing EnergyCreditLedger $ledger"
else
    ledger_json="$(forge create \
        contracts/creditcoin-chain/EnergyCreditLedger.sol:EnergyCreditLedger \
        --rpc-url "$CREDITCOIN_RPC_URL" \
        --account "$DEPLOYER_ACCOUNT" \
    --broadcast \
    "${VERIFY_FLAGS[@]}" \
    --json)"
    ledger="$(jq -r '.deployedTo' <<<"$ledger_json")"
    ledger_tx="$(jq -r '.transactionHash' <<<"$ledger_json")"
    [[ "$ledger" != "null" && -n "$ledger" ]] || { echo "Could not parse ledger address" >&2; exit 1; }
    echo "EnergyCreditLedger $ledger"

    forge verify-contract "$ledger" \
        contracts/creditcoin-chain/EnergyCreditLedger.sol:EnergyCreditLedger \
        --chain 102031 \
        --rpc-url "$CREDITCOIN_RPC_URL" \
        "${VERIFY_FLAGS[@]}" \
        --compiler-version 0.8.30 \
        --num-of-optimizations 200 \
        --evm-version shanghai \
        --creation-transaction-hash "$ledger_tx" \
        --watch
fi

consumer_json="$(forge create \
    contracts/creditcoin-chain/EnergyProofConsumer.sol:EnergyProofConsumer \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    --account "$DEPLOYER_ACCOUNT" \
    --force \
    --broadcast \
    "${VERIFY_FLAGS[@]}" \
    --json \
    --constructor-args "$SOURCE_CHAIN_KEY" "$ENERGY_METER_ADDRESS" "$ledger")"
consumer="$(jq -r '.deployedTo' <<<"$consumer_json")"
consumer_tx="$(jq -r '.transactionHash' <<<"$consumer_json")"
[[ "$consumer" != "null" && -n "$consumer" ]] || { echo "Could not parse consumer address" >&2; exit 1; }
echo "EnergyProofConsumer $consumer"

forge verify-contract "$consumer" \
    contracts/creditcoin-chain/EnergyProofConsumer.sol:EnergyProofConsumer \
    --chain 102031 \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    "${VERIFY_FLAGS[@]}" \
    --compiler-version 0.8.30 \
    --num-of-optimizations 200 \
    --evm-version shanghai \
    --creation-transaction-hash "$consumer_tx" \
    --guess-constructor-args \
    --watch

consumer_role="$(cast call "$ledger" "CONSUMER_ROLE()(bytes32)" --rpc-url "$CREDITCOIN_RPC_URL")"
cast send "$ledger" "grantRole(bytes32,address)" "$consumer_role" "$consumer" \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    --account "$DEPLOYER_ACCOUNT"

echo "Consumer role granted"
