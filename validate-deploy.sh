#!/bin/bash
# Scans through a broadcast file and re-verifies all the contracts that were deployed against a sourcify local instance
# Usage: ./validate-deploy.sh <broadcast-file>
# Please note you need to build with the proper compiler settings before calling this.

if [ -z $1 ]; then
  echo "Usage: ./validate-deploy.sh <broadcast-file>"
  exit 1
fi

# load the json file
json=$(cat $1)

# iterate over transactions and filter by transactionType = "CREATE"
for row in $(echo "${json}" | jq -r -c '.transactions[] | select(.transactionType=="CREATE") | {contractAddress, contractName}'); do
  # extract contractAddress and contractName
  contractAddress=$(echo "$row" | jq -r '.contractAddress')
  contractName=$(echo "$row" | jq -r '.contractName')
  # run the verification command
  forge verify-contract ${contractAddress} ${contractName} --chain-id `cast chain-id` --watch --verifier sourcify --verifier-url http://127.0.0.1:5555/
  if [ $? -ne 0 ]; then
    echo "Contract verification failed for ${contractName} at ${contractAddress}"
    exit 1
  fi
done
