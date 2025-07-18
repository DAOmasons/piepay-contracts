# Local Development Setup

## Contract Addresses
- **PiePay**: `0xcf7ed3acca5a467e9e704c703e8d87f634fb0fc9`
- **MockUSDC**: `0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0`

## Network Configuration
- **RPC URL**: http://localhost:8545
- **Chain ID**: 31337
- **Network Name**: Localhost 8545

## Test Accounts (with 10,000 ETH each)
1. `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` (Deployer)
2. `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
3. `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`

## How to Connect MetaMask
1. Open MetaMask
2. Click networks dropdown
3. Add network manually:
   - Network name: Localhost 8545
   - RPC URL: http://localhost:8545
   - Chain ID: 31337
   - Currency symbol: ETH
4. Import test account using private key:
   `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

## Test Tokens
The deployer account has 1,000,000 MockUSDC automatically minted.
Add MockUSDC to MetaMask using address: `0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0`
To test PiePay, approve spending for MockUSDC if required.
