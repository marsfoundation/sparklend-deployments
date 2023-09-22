#!/bin/bash
# Scans through a broadcast file and verifies all the contracts that were deployed
# Usage: ./validate-deploy.sh <broadcast-file>[ --local]
# Please note you need to build with the proper compiler settings before calling this.
# Set to local to use a local sourcify instance instead of the default etherscan

if [ -z $1 ]; then
  echo "Usage: ./validate-deploy.sh <broadcast-file>[ --local]"
  exit 1
fi

# Load the json file
json=$(cat $1)

# Setup variables based on environment
chainid=$(echo "${json}" | jq -r '.chain')
verifier="etherscan"
verifier_url="https://api.etherscan.io/"
if [ "$2" == "--local" ]; then
  verifier="sourcify"
  verifier_url="http://127.0.0.1:5555/"
else
    # Special case for gnosisscan
    if [ "$chainid" -eq 100 ]; then
        verifier_url="https://api.gnosisscan.io/api"
        export ETHERSCAN_API_KEY=$GNOSISSCAN_API_KEY
    fi
fi

# Iterate over libraries and build the --libraries string
libraries=""
for row in $(echo "${json}" | jq -r '.libraries[]'); do
  # Separate each row into parts
  IFS=':' read -ra parts <<< "$row"
  # Concatenate parts to form the string
  libraries+="--libraries ${parts[0]}:${parts[1]}:${parts[2]} "
done

# Iterate over transactions and filter by transactionType = "CREATE"
failures=0
for row in $(echo "${json}" | jq -r -c '.transactions[] | select(.transactionType=="CREATE") | {contractAddress, contractName}'); do
  # Extract contractAddress and contractName
  contractAddress=$(echo "$row" | jq -r '.contractAddress')
  contractName=$(echo "$row" | jq -r '.contractName')
  # Run the verification command
  forge verify-contract ${contractAddress} ${contractName} ${libraries} --chain-id $chainid --watch --verifier $verifier --verifier-url $verifier_url
  if [ $? -ne 0 ]; then
    failures=$((failures+1))
  fi
done

if [ $failures -gt 0 ]; then
  echo "Failed to verify $failures contracts"
  exit 1
else
  echo "Successfully verified all contracts"
  exit 0
fi
