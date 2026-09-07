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
: "${EVM_V1_DECODER_ADDRESS:?EVM_V1_DECODER_ADDRESS is required}"
: "${ENERGY_METER_ADDRESS:?ENERGY_METER_ADDRESS is required}"
: "${ENERGY_CREDIT_LEDGER_ADDRESS:?ENERGY_CREDIT_LEDGER_ADDRESS is required}"
: "${ENERGY_PROOF_CONSUMER_ADDRESS:?ENERGY_PROOF_CONSUMER_ADDRESS is required}"

constructor_args="$(cast abi-encode \
    'constructor(uint64,address,address)' \
    "$SOURCE_CHAIN_KEY" "$ENERGY_METER_ADDRESS" "$ENERGY_CREDIT_LEDGER_ADDRESS")"

forge verify-contract "$ENERGY_PROOF_CONSUMER_ADDRESS" \
    contracts/creditcoin-chain/EnergyProofConsumer.sol:EnergyProofConsumer \
    --chain 102031 \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    --verifier blockscout \
    --verifier-url "${CREDITCOIN_VERIFIER_URL:-https://creditcoin-testnet.blockscout.com/api/}" \
    --compiler-version 0.8.30 \
    --num-of-optimizations 200 \
    --evm-version shanghai \
    --libraries "node_modules/@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol:EvmV1Decoder:$EVM_V1_DECODER_ADDRESS" \
    --constructor-args "$constructor_args" \
    --watch
