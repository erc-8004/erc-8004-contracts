import { readFileSync } from 'fs';
import { join } from 'path';

// Proxy contracts with their constructor arguments
const proxies = [
  {
    name: "IdentityRegistry Proxy",
    address: "0x80043ed9cf33a3472768dcd53175bb44e03a1e4a",
    implementation: "0x0c342a7342237976236819b3160f9d7ea8c23ac6",
    initData: "0x8129fc1c" // initialize() selector
  },
  {
    name: "ReputationRegistry Proxy",
    address: "0x80045d7b72c47bf5ff73737b780cb1a5ba8ee202",
    implementation: "0x363a785f1c83d375f275fb121ee8087b7e31f5c4",
    // initialize(address identity) calldata
    initData: "0xc4d66de880043ed9cf33a3472768dcd53175bb44e03a1e4a000000000000000000000000"
  },
  {
    name: "ValidationRegistry Proxy",
    address: "0x80041728e0aadf1d1427f9be18d52b7f3afefafb",
    implementation: "0x6251598b4fe45dcadfd2e6dc42b007498073af4a",
    // initialize(address identity) calldata
    initData: "0xc4d66de880043ed9cf33a3472768dcd53175bb44e03a1e4a000000000000000000000000"
  }
];

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

async function verifyProxy(proxy: typeof proxies[0]) {
  console.log(`\n${'═'.repeat(60)}`);
  console.log(`📝 Verifying ${proxy.name}...`);
  console.log(`   Proxy Address: ${proxy.address}`);
  console.log(`   Implementation: ${proxy.implementation}`);
  
  // Get ERC1967Proxy source
  const sources = getAllSources('contracts/ERC1967Proxy.sol');
  console.log(`   Found ${Object.keys(sources).length} source files`);
  
  // Create Standard JSON Input with bytecodeHash: "none"
  const standardJsonInput = {
    language: "Solidity",
    sources,
    settings: {
      evmVersion: "cancun",
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true,
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

  // ERC1967Proxy constructor takes (address implementation, bytes memory _data)
  const constructorArgs = `${proxy.implementation}${proxy.initData.slice(2)}`;

  const data = new URLSearchParams({
    module: 'contract',
    action: 'verifysourcecode',
    contractaddress: proxy.address,
    sourceCode: JSON.stringify(standardJsonInput),
    codeformat: 'solidity-standard-json-input',
    contractname: 'contracts/ERC1967Proxy.sol:ERC1967Proxy',
    compilerversion: 'v0.8.28+commit.7893614a',
    constructorArguments: constructorArgs,
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

async function checkStatus(guid: string, name: string) {
  try {
    const response = await fetch(
      `https://chainscan-galileo.0g.ai/open/api?module=contract&action=checkverifystatus&guid=${guid}`
    );
    const status = await response.json();
    
    if (status.status === '1' && status.result === 'Pass - Verified') {
      console.log(`   ✅ ${name}: VERIFIED!`);
      return true;
    } else {
      console.log(`   ⏳ ${name}: ${status.result || status.message}`);
      return false;
    }
  } catch (error) {
    console.error(`   ❌ Error checking ${name}:`, error);
    return false;
  }
}

async function main() {
  console.log('🚀 Verifying Proxy Contracts (0x8004 addresses)...\n');
  console.log('These are the canonical vanity address proxies.');
  console.log('They use ERC1967Proxy pattern to delegate to implementations.\n');
  
  const guids: { name: string; guid: string; address: string }[] = [];
  
  // Submit all verifications
  for (const proxy of proxies) {
    const guid = await verifyProxy(proxy);
    if (guid) {
      guids.push({ name: proxy.name, guid, address: proxy.address });
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
  console.log('\n⏳ Waiting 20 seconds for verification to complete...\n');
  await new Promise(resolve => setTimeout(resolve, 20000));
  
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
  console.log('\n📋 PROXY VERIFICATION SUMMARY:\n');
  
  guids.forEach((item, idx) => {
    const status = results[idx] ? '✅ VERIFIED' : '⏳ PENDING';
    console.log(`${status} - ${item.name}`);
    console.log(`   ${item.address}`);
    console.log(`   https://chainscan-galileo.0g.ai/address/${item.address}\n`);
  });
  
  const allVerified = results.every(r => r);
  if (allVerified) {
    console.log('🎉 ALL PROXY CONTRACTS VERIFIED! 🎉');
    console.log('\n✅ Complete Deployment:');
    console.log('  - 4 Implementation contracts verified ✓');
    console.log('  - 3 Proxy contracts (0x8004...) verified ✓');
    console.log('  - 1 CREATE2 Factory verified ✓');
    console.log('\n🚀 Ready for production use!');
  } else {
    console.log('⏳ Some verifications still pending. Check the links above.');
  }
  
  console.log(`\n${'═'.repeat(60)}`);
}

main().catch(console.error);

