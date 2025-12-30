import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("ERC8004UpgradeableModule", (m) => {
  // ============================================
  // 1. Deploy IdentityRegistry Implementation & Proxy
  // ============================================
  const identityRegistryImpl = m.contract("IdentityRegistryUpgradeable");

  // Encode initialize() function call (takes no parameters)
  const identityInitData = m.encodeFunctionCall(
    identityRegistryImpl,
    "initialize",
    []
  );

  // Deploy IdentityRegistry Proxy
  const identityProxy = m.contract("ERC1967Proxy", [
    identityRegistryImpl,
    identityInitData,
  ]);

  // ============================================
  // 2. Deploy ReputationRegistry Implementation & Proxy
  // ============================================
  const reputationRegistryImpl = m.contract("ReputationRegistryUpgradeable");

  // Encode initialize(address) function call
  // ReputationRegistry needs the IdentityRegistry proxy address
  const reputationInitData = m.encodeFunctionCall(
    reputationRegistryImpl,
    "initialize",
    [identityProxy]
  );

  // Deploy ReputationRegistry Proxy
  // Using id to differentiate from other ERC1967Proxy deployments
  const reputationProxy = m.contract(
    "ERC1967Proxy",
    [reputationRegistryImpl, reputationInitData],
    {
      id: "ReputationRegistryProxy",
    }
  );

  // ============================================
  // 3. Deploy ValidationRegistry Implementation & Proxy
  // ============================================
  const validationRegistryImpl = m.contract("ValidationRegistryUpgradeable");

  // Encode initialize(address) function call
  // ValidationRegistry needs the IdentityRegistry proxy address
  const validationInitData = m.encodeFunctionCall(
    validationRegistryImpl,
    "initialize",
    [identityProxy]
  );

  // Deploy ValidationRegistry Proxy
  // Using id to differentiate from other ERC1967Proxy deployments
  const validationProxy = m.contract(
    "ERC1967Proxy",
    [validationRegistryImpl, validationInitData],
    {
      id: "ValidationRegistryProxy",
    }
  );

  return {
    // Implementations
    identityRegistryImpl,
    reputationRegistryImpl,
    validationRegistryImpl,

    // Proxies (use these addresses to interact with the contracts)
    identityProxy,
    reputationProxy,
    validationProxy,
  };
});
