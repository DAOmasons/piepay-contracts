#!/bin/bash

# PiePay Testnet Deployment Script
set -e

echo "🚀 PiePay Testnet Deployment Script"
echo "=================================="

# Check if .env file exists
if [ ! -f .env ]; then
    echo "📝 Creating .env file template..."
    cat > .env << EOF
# Sepolia Testnet Configuration
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_PROJECT_ID
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
PRIVATE_KEY=YOUR_PRIVATE_KEY_WITHOUT_0x

# Alternative RPC URLs (choose one):
# SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
# SEPOLIA_RPC_URL=https://rpc.sepolia.org
EOF
    echo "❌ Please fill in your .env file with:"
    echo "   1. Your Infura/Alchemy project ID"
    echo "   2. Your Etherscan API key"
    echo "   3. Your private key (without 0x prefix)"
    echo "   4. Then run this script again"
    exit 1
fi

# Load environment variables
source .env

# Validate environment variables
if [ -z "$SEPOLIA_RPC_URL" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Please set SEPOLIA_RPC_URL and PRIVATE_KEY in .env file"
    exit 1
fi

# Get deployer address
echo "🔍 Checking deployer address..."
DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
echo "   Deployer: $DEPLOYER_ADDRESS"

# Check balance
echo "💰 Checking ETH balance..."
BALANCE=$(cast balance $DEPLOYER_ADDRESS --rpc-url $SEPOLIA_RPC_URL)
BALANCE_ETH=$(cast to-unit $BALANCE ether)
echo "   Balance: $BALANCE_ETH ETH"

# Check if balance is sufficient (need at least 0.01 ETH)
if (( $(echo "$BALANCE_ETH < 0.01" | bc -l) )); then
    echo "❌ Insufficient balance. You need at least 0.01 ETH for deployment"
    echo "   Get Sepolia ETH from: https://sepoliafaucet.com/"
    exit 1
fi

echo "✅ Balance sufficient for deployment"

# Compile contracts
echo "🔨 Compiling contracts..."
forge build

# Deploy to Sepolia
echo "🚀 Deploying to Sepolia testnet..."
forge script script/DeployTestnet.s.sol:DeployTestnet \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv

echo "✅ Deployment completed!"
echo ""
echo "📋 Next steps:"
echo "1. Check deployment.txt for contract addresses"
echo "2. Update frontend config with the PiePay contract address"
echo "3. Test the frontend connection"
echo ""
echo "🔗 Useful links:"
echo "   Sepolia Explorer: https://sepolia.etherscan.io/"
echo "   Sepolia Faucet: https://sepoliafaucet.com/"