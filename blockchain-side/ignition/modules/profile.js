const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("UserProfile", (m) => {
  const userProfile = m.contract("UserProfile", []);
  return { userProfile };
});
