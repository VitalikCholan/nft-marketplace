const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("NFTContract", (m) => {
  // Deploy NFT contract with name and symbol
  const nftContract = m.contract("NFTContract", [
    "NFT Collection", // name
    "NFTC", // symbol
  ]);

  // Set the base URI using a contract call
  const setBaseURI = m.call(nftContract, "setBaseURI", ["ipfs://baseURI/"]);

  return { nftContract, setBaseURI };
});
