#!/bin/bash
# Scans through a broadcast file and verifies all the contracts that were deployed
# Usage: ./validate-deploy.sh <broadcast-file>[ --local]
# Please note you need to build with the proper compiler settings before calling this.
# Set to local to use a local sourcify instance instead of the default etherscan

if [ -z $1 ]; then
  echo "Usage: ./validate-deploy.sh <broadcast-file>[ --local]"
  exit 1
fi

# load the json file
json=$(cat $1)

# setup variables based on environment
chainid=$(echo "${json}" | jq -r '.chain')
verifier="etherscan"
verifier_url="https://api.etherscan.io/"
if [ "$2" == "--local" ]; then
  verifier="sourcify"
  verifier_url="http://127.0.0.1:5555/"
else
    # special case for gnosisscan
    if [ "$chainid" -eq 100 ]; then
        verifier_url="https://api.gnosisscan.io/api"
        export ETHERSCAN_API_KEY=$GNOSISSCAN_API_KEY
    fi
fi

# iterate over libraries and build the --libraries string
libraries=""
for row in $(echo "${json}" | jq -r '.libraries[]'); do
  # separate each row into parts
  IFS=':' read -ra parts <<< "$row"
  # concatenate parts to form the string
  libraries+="--libraries ${parts[0]}:${parts[1]}:${parts[2]} "
done

# iterate over transactions and filter by transactionType = "CREATE"
for row in $(echo "${json}" | jq -r -c '.transactions[] | select(.transactionType=="CREATE") | {contractAddress, contractName}'); do
  # extract contractAddress and contractName
  contractAddress=$(echo "$row" | jq -r '.contractAddress')
  contractName=$(echo "$row" | jq -r '.contractName')
  # run the verification command
  forge verify-contract ${contractAddress} ${contractName} ${libraries} --chain-id $chainid --watch --verifier $verifier --verifier-url $verifier_url
  if [ $? -ne 0 ]; then
    echo "Contract verification failed for ${contractName} at ${contractAddress}"
    exit 1
  fi
done
