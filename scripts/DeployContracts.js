/**
 * DeployContracts.js
 * ------------------
 * Hardhat script that deploys the full QFS Nexus DistroKid Mirror DAO
 * contract suite in the correct order:
 *
 *   1. ArtistNFT      — Guardian NFT / Digital Mirror Twin contract
 *   2. GovernanceDAO  — DAO voting contract (depends on ArtistNFT address)
 *   3. RoyaltyToken   — Example royalty-share token for a sample artist
 *
 * Usage
 * -----
 *   npx hardhat run scripts/DeployContracts.js --network <network>
 *
 * The deployed addresses are printed to stdout and written to
 * `deployments/<network>.json` for reference by other scripts.
 */

const { ethers, network } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address  :", deployer.address);
  console.log(
    "Deployer balance  :",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH"
  );
  console.log("Network           :", network.name);
  console.log("─".repeat(60));

  // ── 1. ArtistNFT ────────────────────────────────────────────────
  console.log("\n[1/3] Deploying ArtistNFT…");
  const ArtistNFT = await ethers.getContractFactory("ArtistNFT");
  const artistNFT = await ArtistNFT.deploy(
    deployer.address, // owner (DAO multi-sig in production)
    true              // soulbound = true by default
  );
  await artistNFT.waitForDeployment();
  const artistNFTAddress = await artistNFT.getAddress();
  console.log("  ArtistNFT deployed to:", artistNFTAddress);

  // ── 2. GovernanceDAO ────────────────────────────────────────────
  console.log("\n[2/3] Deploying GovernanceDAO…");
  const GovernanceDAO = await ethers.getContractFactory("GovernanceDAO");
  const governanceDAO = await GovernanceDAO.deploy(
    artistNFTAddress,   // ArtistNFT address
    deployer.address,   // DAO admin
    3,                  // quorum — minimum 3 participating votes
    3 * 24 * 60 * 60    // voting period — 3 days in seconds
  );
  await governanceDAO.waitForDeployment();
  const governanceDAOAddress = await governanceDAO.getAddress();
  console.log("  GovernanceDAO deployed to:", governanceDAOAddress);

  // ── 3. RoyaltyToken (sample) ────────────────────────────────────
  console.log("\n[3/3] Deploying sample RoyaltyToken…");
  const initialSupply = ethers.parseEther("1000000"); // 1 000 000 tokens
  const RoyaltyToken = await ethers.getContractFactory("RoyaltyToken");
  const royaltyToken = await RoyaltyToken.deploy(
    "Sample Artist",             // artistName
    "DISTROKID-SAMPLE-001",      // distrokidArtistId
    "RTKN-SAMPLE",               // symbol
    initialSupply,               // initialSupply
    deployer.address             // owner
  );
  await royaltyToken.waitForDeployment();
  const royaltyTokenAddress = await royaltyToken.getAddress();
  console.log("  RoyaltyToken deployed to:", royaltyTokenAddress);

  // ── Summary ─────────────────────────────────────────────────────
  console.log("\n" + "─".repeat(60));
  console.log("Deployment complete:");
  console.log("  ArtistNFT     :", artistNFTAddress);
  console.log("  GovernanceDAO :", governanceDAOAddress);
  console.log("  RoyaltyToken  :", royaltyTokenAddress);

  // ── Persist addresses ────────────────────────────────────────────
  const deploymentsDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  const deploymentData = {
    network: network.name,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      ArtistNFT: artistNFTAddress,
      GovernanceDAO: governanceDAOAddress,
      RoyaltyToken: royaltyTokenAddress,
    },
  };

  const outFile = path.join(deploymentsDir, `${network.name}.json`);
  fs.writeFileSync(outFile, JSON.stringify(deploymentData, null, 2));
  console.log(`\nAddresses saved to: ${outFile}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
