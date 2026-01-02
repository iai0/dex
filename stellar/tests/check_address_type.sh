#!/bin/bash

# The address that was failing
ADDRESS="GABB7GY6NOHWRPR7OZTBZJSDXIZDPQ37VRXZQENB44DL2TQOYHHE3R5I"

# Check if it's a G address (Stellar account) or C address (contract)
if [[ $ADDRESS == G* ]]; then
    echo "This is a Stellar account address (G...)"
    echo "Token contracts may need special handling for account addresses"
elif [[ $ADDRESS == C* ]]; then
    echo "This is a contract address (C...)"
else
    echo "Unknown address type"
fi

echo ""
echo "For Soroban token transfers to work with Stellar accounts,"
echo "the account may need to have a trustline or the token needs"
echo "to support the Stellar Asset Contract (SAC) wrapper properly."
