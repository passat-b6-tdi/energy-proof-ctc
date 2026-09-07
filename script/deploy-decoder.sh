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

forge create \
    node_modules/@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol:EvmV1Decoder \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    --account "$DEPLOYER_ACCOUNT" \
    --broadcast \
    --verify \
    --verifier blockscout \
    --verifier-url "${CREDITCOIN_VERIFIER_URL:-https://creditcoin-testnet.blockscout.com/api/}" \
    -vvv
