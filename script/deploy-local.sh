#!/bin/bash

# PiePay Local Development Deployment
set -e

echo "🏠 PiePay Local Development Deployment"
echo "====================================="

# Start local Anvil node in background if not running
if ! pgrep -f "anvil" > /dev/null; then
    echo "🔄 Starting local Anvil node..."
    anvil --host 0.0.0.0 --port 8545 &
    ANVIL_PID=$!
    sleep 2
    echo "✅ Anvil started with PID: $ANVIL_PID"
else
    echo "✅ Anvil node already running"
fi

# Deploy contracts locally
echo "🚀 Deploying contracts to local network..."
forge script script/DeployLocal.s.sol:DeployLocal \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast \
    -vvv

echo "✅ Local deployment completed!"

# Update frontend config for localhost
echo "🔄 Updating frontend config for localhost..."

# Extract addresses from broadcast files
BROADCAST_DIR="./broadcast/DeployLocal.s.sol/31337"
if [ -f "$BROADCAST_DIR/run-latest.json" ]; then
    PIEPAY_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "PiePay") | .contractAddress' "$BROADCAST_DIR/run-latest.json")
    USDC_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "MockUSDC") | .contractAddress' "$BROADCAST_DIR/run-latest.json")
    
    echo "📋 Contract addresses:"
    echo "   MockUSDC: $USDC_ADDRESS"
    echo "   PiePay: $PIEPAY_ADDRESS"
    
    # Update frontend config (with fixed sed for macOS compatibility)
    CONFIG_FILE="../piepay-frontend/src/config.ts"
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
        sed -i.bak "s/PIEPAY: '0x[^']*'/PIEPAY: '$PIEPAY_ADDRESS'/g" "$CONFIG_FILE"
        sed -i.bak "s/PAYMENT_TOKEN: '0x[^']*'/PAYMENT_TOKEN: '$USDC_ADDRESS'/g" "$CONFIG_FILE"  # Adjust key name if different
        echo "✅ Frontend config updated!"
    fi
    
    # Create/overwrite local test info (overwrites if exists, updating with new info)
    cat > ./LOCAL_SETUP.md << EOF
# Local Development Setup

## Contract Addresses
- **PiePay**: \`$PIEPAY_ADDRESS\`
- **MockUSDC**: \`$USDC_ADDRESS\`

## Network Configuration
- **RPC URL**: http://localhost:8545
- **Chain ID**: 31337
- **Network Name**: Localhost 8545

## Test Accounts (with 10,000 ETH each)
1. \`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266\` (Deployer)
2. \`0x70997970C51812dc3A010C7d01b50e0d17dc79C8\`
3. \`0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC\`

## How to Connect MetaMask
1. Open MetaMask
2. Click networks dropdown
3. Add network manually:
   - Network name: Localhost 8545
   - RPC URL: http://localhost:8545
   - Chain ID: 31337
   - Currency symbol: ETH
4. Import test account using private key:
   \`0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80\`

## Test Tokens
The deployer account has approximately 800,000 MockUSDC (after transfers).
The other test accounts (2 and 3) each have 100,000 MockUSDC.
Add MockUSDC to MetaMask using address: \`$USDC_ADDRESS\`
To test PiePay, approve spending for MockUSDC if required.
EOF
    
else
    echo "❌ Could not find deployment broadcast file"
fi

echo ""
echo "🎯 Next steps:"
echo "1. Configure MetaMask for localhost (see LOCAL_SETUP.md)"
echo "2. Start frontend: cd ../piepay-frontend && npm run dev"
echo "3. Connect wallet and test!"
echo ""
echo "💡 Tips:"
echo "   - Use the test accounts provided in LOCAL_SETUP.md"
echo "   - Transactions are instant and free"
echo "   - Reset state anytime by restarting Anvil"
echo "   - For PiePay constructor: Uses hardcoded test values (edit DeployLocal.s.sol to change)"