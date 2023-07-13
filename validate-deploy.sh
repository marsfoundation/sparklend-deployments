#!/bin/bash

# load the json file
json=$(cat $1)

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
  # concatenate to form the string
  forge verify-contract ${contractAddress} ${contractName} --watch --verifier sourcify --verifier-url http://127.0.0.1:5555/
  if [ $? -ne 0 ]; then
    echo "Contract verification failed for ${contractName} at ${contractAddress}"
    exit 1
  fi
done
