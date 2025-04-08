const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("NFTAuction", (m) => {
  const auction = m.contract("NFTAuction", []);
  return { auction };
});
