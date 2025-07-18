#!/bin/bash

# Update Frontend Configuration Script
set -e

echo "🔄 Updating Frontend Configuration"
echo "================================="

# Check if deployment.txt exists
if [ ! -f deployment.txt ]; then
    echo "❌ deployment.txt not found. Please run deployment first."
    exit 1
fi

# Extract contract addresses from deployment.txt
PIEPAY_ADDRESS=$(grep "PiePay:" deployment.txt | cut -d' ' -f2)
USDC_ADDRESS=$(grep "MockUSDC:" deployment.txt | cut -d' ' -f2)

if [ -z "$PIEPAY_ADDRESS" ] || [ -z "$USDC_ADDRESS" ]; then
    echo "❌ Could not extract contract addresses from deployment.txt"
    exit 1
fi

echo "📋 Found contract addresses:"
echo "   PiePay: $PIEPAY_ADDRESS"
echo "   MockUSDC: $USDC_ADDRESS"

# Update frontend config
CONFIG_FILE="../piepay-frontend/src/config.ts"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Frontend config file not found at $CONFIG_FILE"
    exit 1
fi

# Create backup
cp "$CONFIG_FILE" "$CONFIG_FILE.backup"

# Update the config file
sed -i.bak "s/PIEPAY: '0x\.\.\.'/PIEPAY: '$PIEPAY_ADDRESS'/" "$CONFIG_FILE"

echo "✅ Frontend configuration updated!"
echo "   PiePay contract address: $PIEPAY_ADDRESS"
echo "   Backup saved as: $CONFIG_FILE.backup"

# Create a test tokens file for reference
cat > ../piepay-frontend/TEST_TOKENS.md << EOF
# Test Tokens on Sepolia

## MockUSDC Token
- **Address**: \`$USDC_ADDRESS\`
- **Symbol**: USDC
- **Decimals**: 6
- **Purpose**: Payment token for PiePay system

## How to Add to Wallet
1. Open MetaMask
2. Click "Import tokens"
3. Enter contract address: \`$USDC_ADDRESS\`
4. Token symbol should auto-populate as "USDC"
5. Click "Add custom token"

## Getting Test Tokens
The deployer account has 10,000 USDC minted automatically.
You can mint more using the \`mint(address, amount)\` function.

## PiePay Contract
- **Address**: \`$PIEPAY_ADDRESS\`
- **Network**: Sepolia Testnet
- **Explorer**: https://sepolia.etherscan.io/address/$PIEPAY_ADDRESS
EOF

echo "📝 Created TEST_TOKENS.md with token information"
echo ""
echo "🎯 Next steps:"
echo "1. Start the frontend: cd ../piepay-frontend && npm run dev"
echo "2. Connect your wallet to Sepolia testnet"
echo "3. Add the MockUSDC token to your wallet (see TEST_TOKENS.md)"
echo "4. Test the contract interaction!"
echo ""
echo "🔗 Contract on Sepolia Explorer:"
echo "   https://sepolia.etherscan.io/address/$PIEPAY_ADDRESS"