import hre from "hardhat";

/**
 * Fund the owner address with ETH on localhost for testing
 * This script is ONLY for localhost - owner should already have funds on real networks
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  // Owner address (hardcoded from MinimalUUPS.sol line 19)
  const ownerAddress = "0x547289319C3e6aedB179C0b8e8aF0B5ACd062603" as `0x${string}`;

  console.log("Funding Owner Address on Localhost");
  console.log("===================================");
  console.log("Network:", hre.network.name);
  console.log("Deployer address:", deployer.account.address);
  console.log("Owner address:", ownerAddress);
  console.log("");

  // Check network (allow localhost, hardhat, or undefined for local testing)
  const networkName = hre.network.name || "localhost";
  if (networkName !== "localhost" && networkName !== "hardhat") {
    throw new Error("This script is only for localhost/hardhat network. Owner should already have funds on real networks.");
  }

  // Transfer ETH to owner
  console.log("Transferring ETH to owner for gas...");
  const transferAmount = 10000000000000000000n; // 10 ETH
  const transferTxHash = await deployer.sendTransaction({
    to: ownerAddress,
    value: transferAmount,
  });
  await publicClient.waitForTransactionReceipt({ hash: transferTxHash });
  console.log(`   ✅ Transferred ${transferAmount} wei (10 ETH) to owner`);
  console.log("");

  // Check balance
  const balance = await publicClient.getBalance({ address: ownerAddress });
  console.log(`Owner balance: ${balance} wei (${Number(balance) / 1e18} ETH)`);
  console.log("");
  console.log("✅ Owner funded successfully");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
