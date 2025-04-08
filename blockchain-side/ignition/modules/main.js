const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("MainDeployment", (m) => {
  // Deploy NFT Contract first
  const nft = m.contract("NFTContract", [
    "NFT Collection", // name
    "NFTC", // symbol
  ]);

  // Set the base URI for the NFT contract
  const setBaseURI = m.call(nft, "setBaseURI", ["ipfs://baseURI/"]);

  // Deploy Marketplace (no constructor params needed)
  const marketplace = m.contract("NFTMarketplace", []);

  // Deploy User Profile system (no constructor params needed)
  const userProfile = m.contract("UserProfile", []);

  // Deploy Auction system (no constructor params needed)
  const auction = m.contract("NFTAuction", []);

  return {
    nft,
    setBaseURI,
    marketplace,
    userProfile,
    auction,
  };
});
