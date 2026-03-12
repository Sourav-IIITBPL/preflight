#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || exit 1
TARGET="${CRE_TARGET:-staging-settings}"

if ! command -v cre >/dev/null 2>&1; then
  echo "cre CLI not found. Install it first: npm install -g @chainlink/cre-cli"
  exit 1
fi

run_payload() {
  local file="$1"

  if grep -q '"vaultAddress": "0x0000000000000000000000000000000000000000"' "$file"; then
    echo "[SKIP] $file (replace vaultAddress first)"
    return 2
  fi

  echo "[RUN ] $file"
  if cre -R "$ROOT_DIR" workflow simulate ./my-workflow -T "$TARGET" --non-interactive --trigger-index 0 --http-payload "@$file"; then
    echo "[PASS] $file"
    return 0
  fi

  echo "[FAIL] $file"
  return 1
}

pass=0
fail=0
skip=0

while IFS= read -r file; do
  run_payload "$file"
  code=$?
  if [ "$code" -eq 0 ]; then
    pass=$((pass + 1))
  elif [ "$code" -eq 1 ]; then
    fail=$((fail + 1))
  else
    skip=$((skip + 1))
  fi
done < <(find payloads/swap payloads/liquidity payloads/vault -maxdepth 1 -type f -name '*.json' | sort)

echo

echo "Summary: pass=$pass fail=$fail skip=$skip"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
