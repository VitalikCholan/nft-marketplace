const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("TestnetDeployment", (m) => {
  // Deploy NFT Contract with testnet-specific name and symbol
  const nft = m.contract("NFTContract", [
    "NFT Collection Testnet", // Different name for testnet
    "NFTC-TEST", // Different symbol for testnet
  ]);

  // Set testnet-specific base URI (e.g., pointing to testnet IPFS gateway or test metadata)
  const setBaseURI = m.call(nft, "setBaseURI", ["ipfs://testnet-baseURI/"], {
    id: "setBaseURI",
  });

  // Deploy Marketplace with lower listing fee for testing
  const marketplace = m.contract("NFTMarketplace", []);
  const setListingPrice = m.call(
    marketplace,
    "updateListingPrice",
    [
      BigInt("10000000000000000"), // 0.01 ETH in wei for testnet
    ],
    {
      id: "setListingPrice",
    }
  );

  // Deploy User Profile system
  const userProfile = m.contract("UserProfile", []);

  // Deploy Auction system
  const auction = m.contract("NFTAuction", []);

  // Test Setup: Mint test NFTs
  const mintNFT1 = m.call(
    nft,
    "mintWithTraits",
    [
      m.getAccount(0), // mint to deployer (first account)
      "ipfs://testnet-baseURI/1", // metadata URI
      [
        {
          // traits
          traitType: "Background",
          value: "Blue",
        },
      ],
    ],
    {
      id: "mintNFT1",
    }
  );

  const mintNFT2 = m.call(
    nft,
    "mintWithTraits",
    [
      m.getAccount(0), // mint to deployer (first account)
      "ipfs://testnet-baseURI/2", // metadata URI
      [
        {
          // traits
          traitType: "Background",
          value: "Red",
        },
      ],
    ],
    {
      id: "mintNFT2",
    }
  );

  // Test Setup: Create test profile
  const createProfile = m.call(
    userProfile,
    "createProfile",
    [
      "testuser", // username
      "Test user profile", // bio
      "ipfs://testnet-baseURI/avatar", // avatar URI
      "ipfs://testnet-baseURI/cover", // cover URI
    ],
    {
      id: "createProfile",
    }
  );

  // Test Setup: List NFTs for sale
  const approveMarketplace = m.call(
    nft,
    "setApprovalForAll",
    [marketplace, true],
    {
      id: "approveMarketplace",
      after: [mintNFT1, mintNFT2], // Ensure NFTs are minted first
    }
  );

  const listNFT1 = m.call(
    marketplace,
    "listNFT",
    [
      nft,
      "1", // tokenId
      BigInt("100000000000000000"), // 0.1 ETH price
    ],
    {
      value: BigInt("10000000000000000"), // 0.01 ETH listing fee
      id: "listNFT1",
      after: [approveMarketplace], // Ensure approval is done first
    }
  );

  // Test Setup: Create test auction
  const approveAuction = m.call(nft, "setApprovalForAll", [auction, true], {
    id: "approveAuction",
    after: [mintNFT1, mintNFT2], // Ensure NFTs are minted first
  });

  const createAuction = m.call(
    auction,
    "createAuction",
    [
      nft,
      "2", // tokenId
      BigInt("200000000000000000"), // 0.2 ETH starting price
      "86400", // 1 day duration
    ],
    {
      value: BigInt("10000000000000000"), // 0.01 ETH auction fee
      id: "createAuction",
      after: [approveAuction], // Ensure approval is done first
    }
  );

  return {
    nft,
    setBaseURI,
    marketplace,
    setListingPrice,
    userProfile,
    auction,
    // Test setup results
    mintNFT1,
    mintNFT2,
    createProfile,
    approveMarketplace,
    listNFT1,
    approveAuction,
    createAuction,
  };
});
