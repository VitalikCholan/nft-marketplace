const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("NFTMarketplace", (m) => {
  const marketplace = m.contract("NFTMarketplace", []);
  return { marketplace };
});
