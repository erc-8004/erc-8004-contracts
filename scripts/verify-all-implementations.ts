import { readFileSync } from 'fs';
import { join } from 'path';

const contracts = [
  {
    name: "IdentityRegistryUpgradeable",
    address: "0x0c342a7342237976236819b3160f9d7ea8c23ac6",
    sourcePath: "contracts/IdentityRegistryUpgradeable.sol",
    contractName: "contracts/IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable"
  },
  {
    name: "ReputationRegistryUpgradeable",
    address: "0x363a785f1c83d375f275fb121ee8087b7e31f5c4",
    sourcePath: "contracts/ReputationRegistryUpgradeable.sol",
    contractName: "contracts/ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable"
  },
  {
    name: "ValidationRegistryUpgradeable",
    address: "0x6251598b4fe45dcadfd2e6dc42b007498073af4a",
    sourcePath: "contracts/ValidationRegistryUpgradeable.sol",
    contractName: "contracts/ValidationRegistryUpgradeable.sol:ValidationRegistryUpgradeable"
  }
];

// Get all unique imports recursively
function getAllSources(mainFile: string, visited = new Set<string>()): Record<string, { content: string }> {
  const sources: Record<string, { content: string }> = {};
  
  function processFile(filePath: string) {
    if (visited.has(filePath)) return;
    visited.add(filePath);
    
    let fullPath = filePath;
    if (!filePath.startsWith('@')) {
      fullPath = join(process.cwd(), filePath);
    } else {
      fullPath = join(process.cwd(), 'node_modules', filePath);
    }
    
    try {
      const content = readFileSync(fullPath, 'utf-8');
      sources[filePath] = { content };
      
      // Find imports
      const importRegex = /import\s+.*?["'](.+?)["']/g;
      let match;
      while ((match = importRegex.exec(content)) !== null) {
        let importPath = match[1];
        
        // Resolve relative imports
        if (importPath.startsWith('./') || importPath.startsWith('../')) {
          const dir = filePath.substring(0, filePath.lastIndexOf('/'));
          importPath = join(dir, importPath).replace(/\\/g, '/');
        }
        
        processFile(importPath);
      }
    } catch (error) {
      console.warn(`Warning: Could not read ${filePath}`);
    }
  }
  
  processFile(mainFile);
  return sources;
}

async function verifyContract(contract: typeof contracts[0]) {
  console.log(`\n${'═'.repeat(60)}`);
  console.log(`📝 Verifying ${contract.name}...`);
  console.log(`   Address: ${contract.address}`);
  
  // Get all sources including imports
  const sources = getAllSources(contract.sourcePath);
  console.log(`   Found ${Object.keys(sources).length} source files`);
  
  // Create Standard JSON Input
  const standardJsonInput = {
    language: "Solidity",
    sources,
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true,
      evmVersion: "cancun",
      metadata: {
        bytecodeHash: "ipfs"
      },
      outputSelection: {
        "*": {
          "*": ["abi", "evm.bytecode", "evm.deployedBytecode"]
        }
      }
    }
  };

  const data = new URLSearchParams({
    module: 'contract',
    action: 'verifysourcecode',
    contractaddress: contract.address,
    sourceCode: JSON.stringify(standardJsonInput),
    codeformat: 'solidity-standard-json-input',
    contractname: contract.contractName,
    compilerversion: 'v0.8.28+commit.7893614a',
    licenseType: '3'
  });

  try {
    const response = await fetch('https://chainscan-galileo.0g.ai/open/api', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: data.toString()
    });

    const result = await response.json();
    
    if (result.status === '1') {
      console.log(`   ✅ Submitted! GUID: ${result.result}`);
      return result.result;
    } else {
      console.log(`   ❌ Failed: ${result.message}`);
      console.log(`   Result: ${result.result}`);
      return null;
    }
  } catch (error) {
    console.error(`   ❌ Error:`, error);
    return null;
  }
}

async function checkStatus(guid: string, contractName: string) {
  try {
    const response = await fetch(
      `https://chainscan-galileo.0g.ai/open/api?module=contract&action=checkverifystatus&guid=${guid}`
    );
    const status = await response.json();
    
    if (status.status === '1' && status.result === 'Pass - Verified') {
      console.log(`   ✅ ${contractName}: VERIFIED!`);
      return true;
    } else {
      console.log(`   ⏳ ${contractName}: ${status.result || status.message}`);
      return false;
    }
  } catch (error) {
    console.error(`   ❌ Error checking ${contractName}:`, error);
    return false;
  }
}

async function main() {
  console.log('🚀 Verifying Implementation Contracts...\n');
  console.log('This will verify all 3 upgradeable implementation contracts.');
  console.log('Once verified, the proxy contracts will show as verified too!\n');
  
  const guids: { name: string; guid: string; address: string }[] = [];
  
  // Submit all verifications
  for (const contract of contracts) {
    const guid = await verifyContract(contract);
    if (guid) {
      guids.push({ name: contract.name, guid, address: contract.address });
    }
    // Wait between requests
    await new Promise(resolve => setTimeout(resolve, 3000));
  }
  
  if (guids.length === 0) {
    console.log('\n❌ No verifications submitted successfully.');
    return;
  }
  
  // Wait for verification to complete
  console.log(`\n${'═'.repeat(60)}`);
  console.log('\n⏳ Waiting 15 seconds for verification to complete...\n');
  await new Promise(resolve => setTimeout(resolve, 15000));
  
  // Check status of all
  console.log('📊 Checking verification status...\n');
  const results: boolean[] = [];
  for (const { name, guid } of guids) {
    const verified = await checkStatus(guid, name);
    results.push(verified);
    await new Promise(resolve => setTimeout(resolve, 2000));
  }
  
  // Summary
  console.log(`\n${'═'.repeat(60)}`);
  console.log('\n📋 VERIFICATION SUMMARY:\n');
  
  guids.forEach((item, idx) => {
    const status = results[idx] ? '✅ VERIFIED' : '⏳ PENDING';
    console.log(`${status} - ${item.name}`);
    console.log(`   ${item.address}`);
    console.log(`   https://chainscan-galileo.0g.ai/address/${item.address}\n`);
  });
  
  const allVerified = results.every(r => r);
  if (allVerified) {
    console.log('🎉 ALL CONTRACTS VERIFIED! 🎉');
    console.log('\nCanonical Proxy Contracts (0x8004...):');
    console.log('  Identity:    https://chainscan-galileo.0g.ai/address/0x80043ed9cf33a3472768dcd53175bb44e03a1e4a');
    console.log('  Reputation:  https://chainscan-galileo.0g.ai/address/0x80045d7b72c47bf5ff73737b780cb1a5ba8ee202');
    console.log('  Validation:  https://chainscan-galileo.0g.ai/address/0x80041728e0aadf1d1427f9be18d52b7f3afefafb');
  } else {
    console.log('⏳ Some verifications still pending. Check the links above.');
  }
  
  console.log(`\n${'═'.repeat(60)}`);
}

main().catch(console.error);

