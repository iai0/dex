#!/bin/bash

# Check batch contract token balances
BATCH_CONTRACT="CDBULXZAKJRTZ7LXSY6LQ4NBRE3TXO4LPHQXJAAPIDI2S7NCM5UYRDFA"
PXLM_TOKEN="CDT3QTGDXGCTL6DITG4QH5WSCSMVFE5EKKMSW4PVQQUSPVAHD5H2YHM4"
XLM_TOKEN="CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
NETWORK="testnet"

echo "=== Batch Contract Token Balances ==="
echo ""

# Check pXLM balance
echo "pXLM Balance:"
stellar contract invoke \
  --id "$PXLM_TOKEN" \
  --network "$NETWORK" \
  --source SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774 \
  -- \
  balance \
  --id "$BATCH_CONTRACT" 2>&1 | grep -E "^[0-9]+" || echo "0"

echo ""
echo "XLM Balance:"
stellar contract invoke \
  --id "$XLM_TOKEN" \
  --network "$NETWORK" \
  --source SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774 \
  -- \
  balance \
  --id "$BATCH_CONTRACT" 2>&1 | grep -E "^[0-9]+" || echo "0"

