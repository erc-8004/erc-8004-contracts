import hre from "hardhat";
import { getSingletonFactoryInfo } from "@safe-global/safe-singleton-factory";

/**
 * Deploys the Create2 Deployer (Singleton Factory) at 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7
 *
 * This is the deterministic deployment proxy that enables CREATE2 deployments
 * across all EVM networks at the same address.
 *
 * LOCALHOST ONLY - This script is for local development networks only.
 * For production networks, the factory should already be deployed.
 *
 * Reference: https://github.com/safe-global/safe-singleton-factory
 */

const FACTORY_ADDRESS = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

async function main() {
    // Always connect to localhost
    const { viem } = await hre.network.connect("localhost");
    const publicClient = await viem.getPublicClient();
    const [deployer] = await viem.getWalletClients();

    const chainId = await publicClient.getChainId();

    console.log("=".repeat(80));
    console.log("Deploying Create2 Deployer (Singleton Factory) - LOCALHOST");
    console.log("=".repeat(80));
    console.log("Chain ID:", chainId);
    console.log();

    // Check if factory is already deployed
    const existingCode = await publicClient.getBytecode({
        address: FACTORY_ADDRESS,
    });
    if (existingCode !== undefined && existingCode !== "0x") {
        console.log("✅ Factory already deployed at:", FACTORY_ADDRESS);
        console.log("   Bytecode length:", existingCode.length);
        return;
    }

    // Get deployment info for this chain
    const factoryInfo = getSingletonFactoryInfo(chainId);

    if (!factoryInfo) {
        throw new Error(`No singleton factory deployment info for chain ID ${chainId}. The factory may not be available for this network.`);
    }

    console.log("Step 1: Funding deployer address");
    console.log("   Deployer:", factoryInfo.signerAddress);
    console.log("   Gas limit:", factoryInfo.gasLimit);
    console.log("   Gas price:", factoryInfo.gasPrice);
    console.log("   Funding amount:", BigInt(factoryInfo.gasLimit) * BigInt(factoryInfo.gasPrice), "wei");

    // Fund the deployer account
    const fundingAmount = BigInt(factoryInfo.gasLimit) * BigInt(factoryInfo.gasPrice);
    const fundTxHash = await deployer.sendTransaction({
        to: factoryInfo.signerAddress as `0x${string}`,
        value: fundingAmount,
        gas: 21000n,
    });
    console.log("   Transaction hash:", fundTxHash);
    await publicClient.waitForTransactionReceipt({ hash: fundTxHash });
    console.log("   ✅ Funded successfully");
    console.log();

    // Send the pre-signed transaction
    console.log("Step 2: Broadcasting pre-signed deployment transaction");
    const deployTxHash = await publicClient.sendRawTransaction({
        serializedTransaction: factoryInfo.transaction as `0x${string}`,
    });
    console.log("   Transaction hash:", deployTxHash);

    const receipt = await publicClient.waitForTransactionReceipt({ hash: deployTxHash });
    console.log("   ✅ Transaction mined in block:", receipt.blockNumber);
    console.log();

    // Verify deployment
    console.log("Step 3: Verifying deployment");
    const deployedCode = await publicClient.getBytecode({
        address: FACTORY_ADDRESS,
    });

    if (deployedCode !== undefined && deployedCode !== "0x") {
        console.log("   ✅ Factory deployed successfully!");
        console.log("   Address:", FACTORY_ADDRESS);
        console.log("   Bytecode length:", deployedCode.length);
        console.log();
        console.log("=".repeat(80));
        console.log("✅ SUCCESS: Create2 deployer is ready to use");
        console.log("=".repeat(80));
    } else {
        console.log("   ❌ Deployment failed - no code at expected address");
        throw new Error("Factory deployment verification failed");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
