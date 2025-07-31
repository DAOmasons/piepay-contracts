#!/bin/bash

# PiePay Arbitrum Sepolia Deployment Script
set -e

echo "🚀 PiePay Arbitrum Sepolia Deployment Script"
echo "============================================"

# Check if .env file exists
if [ ! -f .env ]; then
    echo "📝 Creating .env file template..."
    cat > .env << EOF
# Arbitrum Sepolia Configuration
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
ARBISCAN_API_KEY=YOUR_ARBISCAN_API_KEY
PRIVATE_KEY=YOUR_PRIVATE_KEY_WITHOUT_0x

# Alternative RPC URLs (choose one):
# ARBITRUM_SEPOLIA_RPC_URL=https://arb-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
# ARBITRUM_SEPOLIA_RPC_URL=https://arbitrum-sepolia.infura.io/v3/YOUR_INFURA_PROJECT_ID
EOF
    echo "❌ Please fill in your .env file with:"
    echo "   1. Your RPC URL (Alchemy/Infura/Public)"
    echo "   2. Your Arbiscan API key (from https://arbiscan.io/apis)"
    echo "   3. Your private key (without 0x prefix)"
    echo "   4. Then run this script again"
    exit 1
fi

# Load environment variables
source .env

# Validate environment variables
if [ -z "$ARBITRUM_SEPOLIA_RPC_URL" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Please set ARBITRUM_SEPOLIA_RPC_URL and PRIVATE_KEY in .env file"
    exit 1
fi

# Get deployer address
echo "🔍 Checking deployer address..."
DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
echo "   Deployer: $DEPLOYER_ADDRESS"

# Check balance
echo "💰 Checking ETH balance..."
BALANCE=$(cast balance $DEPLOYER_ADDRESS --rpc-url $ARBITRUM_SEPOLIA_RPC_URL)
BALANCE_ETH=$(cast to-unit $BALANCE ether)
echo "   Balance: $BALANCE_ETH ETH"

# Check if balance is sufficient (need at least 0.01 ETH)
if (( $(echo "$BALANCE_ETH < 0.01" | bc -l) )); then
    echo "❌ Insufficient balance. You need at least 0.01 ETH for deployment"
    echo "   Get Arbitrum Sepolia ETH from:"
    echo "   - https://faucet.triangleplatform.com/arbitrum/sepolia"
    echo "   - https://faucet.quicknode.com/arbitrum/sepolia"
    echo "   - Bridge from Ethereum Sepolia: https://bridge.arbitrum.io/"
    exit 1
fi

echo "✅ Balance sufficient for deployment"

# Compile contracts
echo "🔨 Compiling contracts..."
forge build

# Deploy to Arbitrum Sepolia
echo "🚀 Deploying to Arbitrum Sepolia..."
if [ -n "$ARBISCAN_API_KEY" ]; then
    echo "   With contract verification..."
    forge script script/DeployArbitrumSepolia.s.sol:DeployArbitrumSepolia \
        --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
        --broadcast \
        --verify \
        --etherscan-api-key $ARBISCAN_API_KEY \
        --verifier-url https://api-sepolia.arbiscan.io/api \
        -vvvv
else
    echo "   Without verification (no ARBISCAN_API_KEY provided)..."
    forge script script/DeployArbitrumSepolia.s.sol:DeployArbitrumSepolia \
        --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
        --broadcast \
        -vvvv
fi

echo "✅ Deployment completed!"
echo ""
echo "📋 Next steps:"
echo "1. Check arbitrum-sepolia-deployment.txt for contract addresses"
echo "2. Update frontend config with the PiePay contract address"
echo "3. Test the frontend connection"
echo ""
echo "🔗 Useful links:"
echo "   Arbitrum Sepolia Explorer: https://sepolia.arbiscan.io/"
echo "   Arbitrum Bridge: https://bridge.arbitrum.io/"
echo "   Faucets:"
echo "   - https://faucet.triangleplatform.com/arbitrum/sepolia"
echo "   - https://faucet.quicknode.com/arbitrum/sepolia"