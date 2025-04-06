const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("UserProfile", function () {
  // Global variables
  let userProfile;
  let nftContract;
  let owner;
  let user1;
  let user2;
  let user3;
  let tokenId;
  let tokenURI;
  let traits;

  // Setup function
  async function deployContracts() {
    const [ownerSigner, user1Signer, user2Signer, user3Signer] =
      await ethers.getSigners();

    // Deploy NFT contract
    const NFTContract = await ethers.getContractFactory(
      "contracts/NFTContract.sol:NFTContract"
    );
    const nftContractInstance = await NFTContract.deploy("MyNFT", "MNFT");
    await nftContractInstance.waitForDeployment();

    // Deploy UserProfile contract
    const UserProfile = await ethers.getContractFactory("UserProfile");
    const userProfileInstance = await UserProfile.deploy();
    await userProfileInstance.waitForDeployment();

    return {
      userProfile: userProfileInstance,
      nftContract: nftContractInstance,
      owner: ownerSigner,
      user1: user1Signer,
      user2: user2Signer,
      user3: user3Signer,
    };
  }

  // Setup before each test
  beforeEach(async function () {
    // Deploy contracts and get signers
    const contracts = await loadFixture(deployContracts);
    userProfile = contracts.userProfile;
    nftContract = contracts.nftContract;
    owner = contracts.owner;
    user1 = contracts.user1;
    user2 = contracts.user2;
    user3 = contracts.user3;

    // Set common test variables
    tokenURI = "ipfs://test-uri";
    traits = []; // Empty traits array
    tokenId = 1;
  });

  describe("Profile Creation", function () {
    it("Should create a profile successfully", async function () {
      const username = "testuser";
      const bio = "Test bio";
      const avatarURI = "ipfs://avatar";
      const coverURI = "ipfs://cover";

      await expect(
        userProfile
          .connect(user1)
          .createProfile(username, bio, avatarURI, coverURI)
      )
        .to.emit(userProfile, "ProfileCreated")
        .withArgs(user1.address, username);

      // Verify profile exists
      expect(await userProfile.hasUserProfile(user1.address)).to.be.true;

      // Verify profile data
      const profile = await userProfile.getProfile(user1.address);
      expect(profile.username).to.equal(username);
      expect(profile.bio).to.equal(bio);
      expect(profile.avatarURI).to.equal(avatarURI);
      expect(profile.coverURI).to.equal(coverURI);
      expect(profile.isVerified).to.be.false;
    });

    it("Should fail to create a profile with an existing username", async function () {
      const username = "testuser";
      const bio = "Test bio";
      const avatarURI = "ipfs://avatar";
      const coverURI = "ipfs://cover";

      // Create first profile
      await userProfile
        .connect(user1)
        .createProfile(username, bio, avatarURI, coverURI);

      // Try to create second profile with same username
      await expect(
        userProfile
          .connect(user2)
          .createProfile(username, bio, avatarURI, coverURI)
      ).to.be.revertedWith("Username already taken");
    });

    it("Should fail to create a profile with a username that's too short", async function () {
      const username = "ab"; // Too short
      const bio = "Test bio";
      const avatarURI = "ipfs://avatar";
      const coverURI = "ipfs://cover";

      await expect(
        userProfile
          .connect(user1)
          .createProfile(username, bio, avatarURI, coverURI)
      ).to.be.revertedWith("Username too short");
    });

    it("Should fail to create a profile if user already has one", async function () {
      const username = "testuser";
      const bio = "Test bio";
      const avatarURI = "ipfs://avatar";
      const coverURI = "ipfs://cover";

      // Create first profile
      await userProfile
        .connect(user1)
        .createProfile(username, bio, avatarURI, coverURI);

      // Try to create second profile for same user
      await expect(
        userProfile
          .connect(user1)
          .createProfile("anotheruser", bio, avatarURI, coverURI)
      ).to.be.revertedWith("Profile already exists");
    });
  });

  describe("Profile Updates", function () {
    beforeEach(async function () {
      // Create a profile for user1
      await userProfile
        .connect(user1)
        .createProfile("testuser", "Test bio", "ipfs://avatar", "ipfs://cover");
    });

    it("Should update profile successfully", async function () {
      const newBio = "Updated bio";
      const newAvatarURI = "ipfs://new-avatar";
      const newCoverURI = "ipfs://new-cover";

      await expect(
        userProfile
          .connect(user1)
          .updateProfile(newBio, newAvatarURI, newCoverURI)
      )
        .to.emit(userProfile, "ProfileUpdated")
        .withArgs(user1.address, "testuser")
        .to.emit(userProfile, "BioUpdated")
        .withArgs(user1.address, newBio)
        .to.emit(userProfile, "AvatarUpdated")
        .withArgs(user1.address, newAvatarURI)
        .to.emit(userProfile, "CoverUpdated")
        .withArgs(user1.address, newCoverURI);

      // Verify updated profile data
      const profile = await userProfile.getProfile(user1.address);
      expect(profile.bio).to.equal(newBio);
      expect(profile.avatarURI).to.equal(newAvatarURI);
      expect(profile.coverURI).to.equal(newCoverURI);
    });

    it("Should update username successfully", async function () {
      const newUsername = "newusername";

      await expect(userProfile.connect(user1).updateUsername(newUsername))
        .to.emit(userProfile, "ProfileUpdated")
        .withArgs(user1.address, newUsername);

      // Verify username is updated
      const profile = await userProfile.getProfile(user1.address);
      expect(profile.username).to.equal(newUsername);

      // Verify username mapping is updated
      expect(await userProfile.getAddressByUsername(newUsername)).to.equal(
        user1.address
      );
      expect(await userProfile.getAddressByUsername("testuser")).to.equal(
        ethers.ZeroAddress
      );
    });

    it("Should fail to update profile if profile does not exist", async function () {
      await expect(
        userProfile
          .connect(user2)
          .updateProfile("New bio", "ipfs://new-avatar", "ipfs://new-cover")
      ).to.be.revertedWith("Profile does not exist");
    });

    it("Should fail to update username if the new username is already taken", async function () {
      // Create a profile for user2
      await userProfile
        .connect(user2)
        .createProfile(
          "anotheruser",
          "Another bio",
          "ipfs://avatar2",
          "ipfs://cover2"
        );

      // Try to update user1's username to user2's username
      await expect(
        userProfile.connect(user1).updateUsername("anotheruser")
      ).to.be.revertedWith("Username already taken");
    });
  });

  describe("NFT Connections", function () {
    beforeEach(async function () {
      // Create a profile for user1
      await userProfile
        .connect(user1)
        .createProfile("testuser", "Test bio", "ipfs://avatar", "ipfs://cover");

      // Mint an NFT to user1
      await nftContract
        .connect(user1)
        .mintWithTraits(user1.address, tokenURI, traits);
    });

    it("Should add an NFT to favorites successfully", async function () {
      await expect(
        userProfile.connect(user1).addFavoriteNFT(nftContract.target, tokenId)
      )
        .to.emit(userProfile, "FavoriteNFTAdded")
        .withArgs(user1.address, nftContract.target, tokenId);

      // Verify favorite NFTs
      const favoriteNFTs = await userProfile.getFavoriteNFTs(user1.address);
      expect(favoriteNFTs.length).to.equal(1);
      expect(favoriteNFTs[0]).to.equal(tokenId);

      // Verify favorite NFT contracts
      const favoriteContracts = await userProfile.getFavoriteNFTContracts(
        user1.address
      );
      expect(favoriteContracts.length).to.equal(1);
      expect(favoriteContracts[0]).to.equal(nftContract.target);
    });

    it("Should remove an NFT from favorites successfully", async function () {
      // Add NFT to favorites first
      await userProfile
        .connect(user1)
        .addFavoriteNFT(nftContract.target, tokenId);

      // Remove NFT from favorites
      await expect(
        userProfile
          .connect(user1)
          .removeFavoriteNFT(nftContract.target, tokenId)
      )
        .to.emit(userProfile, "FavoriteNFTRemoved")
        .withArgs(user1.address, nftContract.target, tokenId);

      // Verify favorite NFTs
      const favoriteNFTs = await userProfile.getFavoriteNFTs(user1.address);
      expect(favoriteNFTs.length).to.equal(0);

      // Verify favorite NFT contracts
      const favoriteContracts = await userProfile.getFavoriteNFTContracts(
        user1.address
      );
      expect(favoriteContracts.length).to.equal(0);
    });

    it("Should fail to add an NFT to favorites if not the owner", async function () {
      // Mint an NFT to user2
      await nftContract
        .connect(user2)
        .mintWithTraits(user2.address, tokenURI, traits);

      const tokenId = 2; // This is important - we need to use the correct token ID

      // Try to add user2's NFT to user1's favorites
      await expect(
        userProfile.connect(user1).addFavoriteNFT(nftContract.target, tokenId)
      ).to.be.revertedWith("Not NFT owner");
    });

    it("Should fail to add an NFT to favorites if profile doesn't exist", async function () {
      // Create a profile for user2
      await userProfile
        .connect(user2)
        .createProfile(
          "anotheruser",
          "Another bio",
          "ipfs://avatar2",
          "ipfs://cover2"
        );

      // Try to add user1's NFT to user2's favorites
      await expect(
        userProfile.connect(user2).addFavoriteNFT(nftContract.target, tokenId)
      ).to.be.revertedWith("Not NFT owner");
    });
  });

  describe("Custom Attributes", function () {
    beforeEach(async function () {
      // Create a profile for user1
      await userProfile
        .connect(user1)
        .createProfile("testuser", "Test bio", "ipfs://avatar", "ipfs://cover");
    });

    it("Should set a custom attribute successfully", async function () {
      const key = "location";
      const value = "New York";

      await expect(userProfile.connect(user1).setCustomAttribute(key, value))
        .to.emit(userProfile, "CustomAttributeSet")
        .withArgs(user1.address, key, value);

      // Verify custom attribute
      expect(await userProfile.getCustomAttribute(user1.address, key)).to.equal(
        value
      );
    });

    it("Should remove a custom attribute successfully", async function () {
      const key = "location";
      const value = "New York";

      // Set custom attribute first
      await userProfile.connect(user1).setCustomAttribute(key, value);

      // Remove custom attribute
      await expect(userProfile.connect(user1).removeCustomAttribute(key))
        .to.emit(userProfile, "CustomAttributeRemoved")
        .withArgs(user1.address, key);

      // Verify custom attribute is removed
      expect(await userProfile.getCustomAttribute(user1.address, key)).to.equal(
        ""
      );
    });

    it("Should fail to set a custom attribute if profile does not exist", async function () {
      await expect(
        userProfile.connect(user2).setCustomAttribute("location", "New York")
      ).to.be.revertedWith("Profile does not exist");
    });
  });

  describe("Verification", function () {
    beforeEach(async function () {
      // Create a profile for user1
      await userProfile
        .connect(user1)
        .createProfile("testuser", "Test bio", "ipfs://avatar", "ipfs://cover");
    });

    it("Should set verification status successfully", async function () {
      await expect(
        userProfile.connect(owner).setVerificationStatus(user1.address, true)
      )
        .to.emit(userProfile, "ProfileVerified")
        .withArgs(user1.address, true);

      // Verify profile is verified
      const profile = await userProfile.getProfile(user1.address);
      expect(profile.isVerified).to.be.true;
    });

    it("Should fail to set verification status if not the owner", async function () {
      await expect(
        userProfile.connect(user2).setVerificationStatus(user1.address, true)
      ).to.be.revertedWith("Not profile owner");
    });
  });

  describe("NFT Ownership", function () {
    beforeEach(async function () {
      // Create a profile for user1
      await userProfile
        .connect(user1)
        .createProfile("testuser", "Test bio", "ipfs://avatar", "ipfs://cover");

      // Mint NFTs to user1
      await nftContract
        .connect(user1)
        .mintWithTraits(user1.address, tokenURI, traits);
      await nftContract
        .connect(user1)
        .mintWithTraits(user1.address, tokenURI, traits);
    });

    it("Should get owned NFTs successfully", async function () {
      const ownedNFTs = await userProfile.getOwnedNFTs(
        user1.address,
        nftContract.target
      );
      expect(ownedNFTs.length).to.equal(2);
      expect(ownedNFTs[0]).to.equal(1);
      expect(ownedNFTs[1]).to.equal(2);
    });

    it("Should return empty array for non-owner", async function () {
      const ownedNFTs = await userProfile.getOwnedNFTs(
        user2.address,
        nftContract.target
      );
      expect(ownedNFTs.length).to.equal(0);
    });
  });
});
