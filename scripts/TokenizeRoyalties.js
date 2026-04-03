/**
 * TokenizeRoyalties.js
 * --------------------
 * Hardhat script that tokenizes an artist's royalty stream by:
 *
 *   1. Connecting to a deployed RoyaltyToken contract.
 *   2. Minting a specified amount of royalty-share tokens to the artist's
 *      wallet address, representing their proportional claim on future
 *      royalty distributions.
 *   3. Optionally distributing an ETH royalty payment to all current holders.
 *
 * Usage
 * -----
 *   npx hardhat run scripts/TokenizeRoyalties.js --network <network>
 *
 * Environment / configuration
 * ---------------------------
 * Edit the CONFIG object below or pass values via environment variables:
 *
 *   ROYALTY_TOKEN_ADDRESS  — deployed RoyaltyToken contract address
 *   ARTIST_WALLET          — recipient wallet for newly minted shares
 *   MINT_AMOUNT            — token amount to mint (in whole tokens, no decimals)
 *   DISTRIBUTE_ETH         — "true" to also call distributeRoyalties()
 *   DISTRIBUTE_AMOUNT_ETH  — ETH amount to distribute (e.g. "0.1")
 */

const { ethers, network } = require("hardhat");

// ── Configuration ──────────────────────────────────────────────────────────────
const CONFIG = {
  royaltyTokenAddress:
    process.env.ROYALTY_TOKEN_ADDRESS || "0x0000000000000000000000000000000000000000",
  artistWallet:
    process.env.ARTIST_WALLET || "0x0000000000000000000000000000000000000000",
  mintAmount: process.env.MINT_AMOUNT || "10000", // whole tokens
  distributeEth: process.env.DISTRIBUTE_ETH === "true",
  distributeAmountEth: process.env.DISTRIBUTE_AMOUNT_ETH || "0",
};

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Network           :", network.name);
  console.log("Operator address  :", deployer.address);
  console.log("RoyaltyToken addr :", CONFIG.royaltyTokenAddress);
  console.log("─".repeat(60));

  // Attach to the deployed RoyaltyToken
  const RoyaltyToken = await ethers.getContractFactory("RoyaltyToken");
  const royaltyToken = RoyaltyToken.attach(CONFIG.royaltyTokenAddress);

  const artistName = await royaltyToken.artistName();
  const distrokidId = await royaltyToken.distrokidArtistId();
  const symbol = await royaltyToken.symbol();

  console.log("Token             :", symbol);
  console.log("Artist            :", artistName);
  console.log("DistroKid ID      :", distrokidId);
  console.log("─".repeat(60));

  // ── Mint royalty-share tokens ───────────────────────────────────
  const mintAmount = ethers.parseEther(CONFIG.mintAmount);
  const artistWallet = CONFIG.artistWallet;

  console.log(`\nMinting ${CONFIG.mintAmount} ${symbol} to ${artistWallet}…`);
  const mintTx = await royaltyToken.mint(artistWallet, mintAmount);
  const mintReceipt = await mintTx.wait();
  console.log("  Mint tx hash:", mintReceipt.hash);
  console.log("  Gas used    :", mintReceipt.gasUsed.toString());

  const newBalance = await royaltyToken.balanceOf(artistWallet);
  console.log(
    "  New balance :",
    ethers.formatEther(newBalance),
    symbol
  );

  const totalSupply = await royaltyToken.totalSupply();
  console.log(
    "  Total supply:",
    ethers.formatEther(totalSupply),
    symbol
  );

  // ── Optional ETH royalty distribution ──────────────────────────
  if (CONFIG.distributeEth && parseFloat(CONFIG.distributeAmountEth) > 0) {
    const ethAmount = ethers.parseEther(CONFIG.distributeAmountEth);
    console.log(
      `\nDistributing ${CONFIG.distributeAmountEth} ETH to all holders…`
    );

    const distTx = await royaltyToken.distributeRoyalties({
      value: ethAmount,
    });
    const distReceipt = await distTx.wait();
    console.log("  Distribution tx hash:", distReceipt.hash);
    console.log("  Gas used:", distReceipt.gasUsed.toString());

    const totalDistributed = await royaltyToken.totalRoyaltiesDistributed();
    console.log(
      "  Total distributed so far:",
      ethers.formatEther(totalDistributed),
      "ETH"
    );
  }

  console.log("\n✓ Royalty tokenization complete.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
