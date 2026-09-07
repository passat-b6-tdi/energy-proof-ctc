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
: "${ENERGY_CREDIT_LEDGER_ADDRESS:?ENERGY_CREDIT_LEDGER_ADDRESS is required}"
: "${ENERGY_PROOF_CONSUMER_ADDRESS:?ENERGY_PROOF_CONSUMER_ADDRESS is required}"

consumer_role="$(cast call "$ENERGY_CREDIT_LEDGER_ADDRESS" "CONSUMER_ROLE()(bytes32)" \
    --rpc-url "$CREDITCOIN_RPC_URL")"
cast send "$ENERGY_CREDIT_LEDGER_ADDRESS" "grantRole(bytes32,address)" \
    "$consumer_role" "$ENERGY_PROOF_CONSUMER_ADDRESS" \
    --rpc-url "$CREDITCOIN_RPC_URL" \
    --account "$DEPLOYER_ACCOUNT"

echo "Consumer role granted"
