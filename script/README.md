# Deployment Scripts

This directory contains both Foundry deployment scripts (`.s.sol`) and shell utility scripts (`.sh`) for the PiePay contract system.

## Foundry Scripts

### `Deploy.s.sol`
Main deployment script for production environments.

### `DeployLocal.s.sol`
Local deployment script for development with Anvil.

### `DeployTestnet.s.sol`
Testnet deployment script with additional setup.

## Shell Utilities

### `deploy-local.sh`
Quick local deployment wrapper that:
- Starts Anvil if not running
- Deploys contracts using `DeployLocal.s.sol`
- Outputs deployment info to `deployment.txt`

**Usage:**
```bash
cd script
./deploy-local.sh
```

### `deploy.sh`
General deployment script for any network.

**Usage:**
```bash
cd script
./deploy.sh
```

### `update-frontend.sh`
Post-deployment utility that:
- Reads contract addresses from `deployment.txt`
- Updates frontend configuration files
- Creates test token documentation
- Provides setup instructions

**Usage:**
```bash
cd script
./update-frontend.sh
```

## Typical Workflow

1. **Local Development:**
   ```bash
   cd script
   ./deploy-local.sh
   ./update-frontend.sh
   ```

2. **Testnet Deployment:**
   ```bash
   cd script
   forge script DeployTestnet.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
   ./update-frontend.sh
   ```

## Output Files

- `deployment.txt` - Contract addresses and deployment info
- `../piepay-frontend/TEST_TOKENS.md` - Token setup instructions
- `../piepay-frontend/src/config.ts` - Updated frontend configuration