#!/bin/bash

# Deploy PiePayFactory to Arbitrum Sepolia
echo "Deploying PiePayFactory to Arbitrum Sepolia..."

forge script script/DeployFactoryArbitrumSepolia.s.sol \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  --watch \
  -vvvv

echo "Deployment complete!"