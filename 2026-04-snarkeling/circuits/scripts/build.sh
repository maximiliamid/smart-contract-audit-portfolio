#!/usr/bin/env bash

###############################################################################
# build.sh
#
# Generates Noir/Barretenberg proof artifacts and Foundry fixtures for the
# Treasure Hunt project.
#
# Summary
# -------
# - Reads candidate `treasure` and `treasure_hash` arrays from
#   `circuits/Prover.toml.example`
# - Selects one pair using `TREASURE_INDEX`
# - Writes a runtime `circuits/Prover.toml`
# - Runs `nargo execute`
# - Generates proof + verification key via `bb prove`
# - Generates `contracts/src/Verifier.sol`
# - Writes Foundry fixtures:
#     * contracts/test/fixtures/proof.bin
#     * contracts/test/fixtures/public_inputs.json
#
# Expected proof interface
# ------------------------
# Private input:
#   - treasure
#
# Public inputs:
#   - treasure_hash
#   - recipient
#
# Usage
# -----
#   ./build.sh
#   TREASURE_INDEX=4 ./build.sh
#
# Requirements
# ------------
# Commands required in PATH:
#   - nargo
#   - bb
#   - cast
#   - awk
#
# Notes
# -----
# - `Prover.toml.example` must contain matching `treasure` and `treasure_hash`
#   arrays plus a scalar `recipient`.
# - The selected pair is copied into a scalar runtime `Prover.toml` so the
#   existing Solidity contract and tests remain unchanged.
# - The generated verifier contract is overwritten on each run.
#
###############################################################################


set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CIRCUITS_DIR="$ROOT_DIR/circuits"
CONTRACTS_SRC_DIR="$ROOT_DIR/contracts/src"
FIXTURES_DIR="$ROOT_DIR/contracts/test/fixtures"

mkdir -p "$FIXTURES_DIR"

# Select which treasure/hash pair to use from Prover.toml.example
TREASURE_INDEX="${TREASURE_INDEX:-0}"

PROVER_SOURCE="$CIRCUITS_DIR/Prover.toml.example"
PROVER_RUNTIME="$CIRCUITS_DIR/Prover.toml"

# -----------------------------
# Helpers
# -----------------------------

# Read scalar value from TOML:
# recipient = "123"
toml_get_scalar() {
  local file="$1"
  local key="$2"

  awk -v k="$key" '
    BEGIN { FS="=" }
    $1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
      v=$2
      sub(/#.*/, "", v)                                # strip inline comments
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)      # trim
      gsub(/^"|"$/, "", v)                            # strip surrounding quotes
      print v
      exit
    }
  ' "$file"
}

# Read item N from a TOML array:
# treasure = [
#   "1",
#   "2",
#   ...
# ]
toml_get_array_item() {
  local file="$1"
  local key="$2"
  local idx="$3"

  awk -v k="$key" -v idx="$idx" '
    BEGIN {
      capture = 0
      buf = ""
      item_index = 0
    }
    {
      line = $0
      sub(/#.*/, "", line)  # strip comments

      # detect the start of the target array
      if (!capture && line ~ "^[[:space:]]*" k "[[:space:]]*=") {
        capture = 1
        sub(/^[^=]*=[[:space:]]*/, "", line)
      }

      if (capture) {
        buf = buf " " line

        # once we see ], parse the accumulated buffer
        if (line ~ /\]/) {
          gsub(/\[/, "", buf)
          gsub(/\]/, "", buf)

          n = split(buf, arr, ",")
          for (i = 1; i <= n; i++) {
            item = arr[i]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
            gsub(/^"|"$/, "", item)

            if (item != "") {
              if (item_index == idx) {
                print item
                exit
              }
              item_index++
            }
          }

          # if idx not found, exit without output
          exit
        }
      }
    }
  ' "$file"
}

# -----------------------------
# Main flow
# -----------------------------

echo "==> (1) Compile/check Noir circuit"
cd "$CIRCUITS_DIR"
nargo check

echo "==> (2) Ensure Prover.toml.example exists"
if [ ! -f "$PROVER_SOURCE" ]; then
  echo "ERROR: Missing source file: $PROVER_SOURCE"
  echo "Create Prover.toml.example with treasure[10], treasure_hash[10], and recipient."
  exit 1
fi

echo "==> (3) Read selected treasure/hash pair from Prover.toml.example"
recipient_dec="$(toml_get_scalar "$PROVER_SOURCE" recipient)"
treasure_dec="$(toml_get_array_item "$PROVER_SOURCE" treasure "$TREASURE_INDEX")"
treasure_hash_dec="$(toml_get_array_item "$PROVER_SOURCE" treasure_hash "$TREASURE_INDEX")"

if [ -z "$recipient_dec" ]; then
  echo "ERROR: Could not read 'recipient' from $PROVER_SOURCE"
  exit 1
fi

if [ -z "$treasure_dec" ]; then
  echo "ERROR: Could not read treasure[$TREASURE_INDEX] from $PROVER_SOURCE"
  exit 1
fi

if [ -z "$treasure_hash_dec" ]; then
  echo "ERROR: Could not read treasure_hash[$TREASURE_INDEX] from $PROVER_SOURCE"
  exit 1
fi

echo "     Selected index:        $TREASURE_INDEX"
echo "     Selected treasure:     $treasure_dec"
echo "     Selected treasureHash: $treasure_hash_dec"
echo "     Recipient:             $recipient_dec"

echo "==> (4) Generate runtime Prover.toml for the selected pair"
cat > "$PROVER_RUNTIME" <<EOF
# Auto-generated from Prover.toml.example
# Selected index: $TREASURE_INDEX

treasure = "$treasure_dec"
treasure_hash = "$treasure_hash_dec"
recipient = "$recipient_dec"
EOF

echo "==> (5) Execute circuit -> witness"
nargo execute

ARTIFACT="$CIRCUITS_DIR/target/snarkeling.json"
WITNESS="$CIRCUITS_DIR/target/snarkeling.gz"

echo "==> (6) Generate proof and verification key (keccak oracle for EVM verification)"
bb prove \
  -b "$ARTIFACT" \
  -w "$WITNESS" \
  -o "$CIRCUITS_DIR/target" \
  --oracle_hash keccak \
  --write_vk

echo "==> (7) Generate Solidity verifier from vk"
bb write_solidity_verifier \
  -k "$CIRCUITS_DIR/target/vk" \
  -o "$CONTRACTS_SRC_DIR/Verifier.sol"

echo "==> (8) Copy proof to Foundry fixtures"
cp "$CIRCUITS_DIR/target/proof" "$FIXTURES_DIR/proof.bin"

echo "==> (9) Create public_inputs.json for Solidity tests"
treasure_hash_hex="$(cast to-hex "$treasure_hash_dec")"
recipient_hex="$(cast to-hex "$recipient_dec")"

treasure_hash_b32="$(cast pad --left --len 32 "$treasure_hash_hex")"
recipient_b32="$(cast pad --left --len 32 "$recipient_hex")"

cat > "$FIXTURES_DIR/public_inputs.json" <<EOF
{
  "selectedIndex": $TREASURE_INDEX,
  "publicInputs": ["$treasure_hash_b32", "$recipient_b32"]
}
EOF

echo "==> (10) Done"
echo "     Runtime TOML: $PROVER_RUNTIME"
echo "     Verifier:     $CONTRACTS_SRC_DIR/Verifier.sol"
echo "     Proof:        $FIXTURES_DIR/proof.bin"
echo "     Inputs:       $FIXTURES_DIR/public_inputs.json"
