const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NFTMarketplace", function () {
  async function deployContracts() {
    const [owner, user1, user2, user3] = await ethers.getSigners();

    // Deploy NFTContract first
    const NFTContract = await ethers.deployContract("NFTContract", [
      "MyNFT",
      "MNFT",
    ]);
    await NFTContract.waitForDeployment();

    // Deploy marketplace
    const NFTMarketplace = await ethers.deployContract("NFTMarketplace");
    await NFTMarketplace.waitForDeployment();

    return {
      nftContract: NFTContract,
      nftMarketplace: NFTMarketplace,
      owner,
      user1,
      user2,
      user3,
    };
  }

  // Common variables used across tests
  let nftContract, nftMarketplace, owner, user1, user2, user3;
  let tokenId, price, listingPrice;

  // Setup before each test
  beforeEach(async function () {
    const fixture = await loadFixture(deployContracts);
    nftContract = fixture.nftContract;
    nftMarketplace = fixture.nftMarketplace;
    owner = fixture.owner;
    user1 = fixture.user1;
    user2 = fixture.user2;
    user3 = fixture.user3;

    // Common values
    tokenId = 1;
    price = ethers.parseEther("1");
    listingPrice = ethers.parseEther("0.01");
  });

  // Helper function to mint and list an NFT
  async function mintAndListNFT(seller, tokenId, price, listingPrice) {
    // Mint NFT to seller
    await nftContract
      .connect(seller)
      .mintWithTraits(seller.address, "ipfs://tokenURI", [
        { traitType: "Background", value: "Blue" },
      ]);

    // Approve marketplace
    await nftContract
      .connect(seller)
      .setApprovalForAll(nftMarketplace.target, true);

    // List NFT
    await nftMarketplace
      .connect(seller)
      .listNFT(nftContract.target, tokenId, price, { value: listingPrice });
  }

  describe("Deployment", function () {
    it("Should deploy both contracts", async function () {
      expect(await nftMarketplace.owner()).to.equal(owner.address);
      expect(await nftContract.owner()).to.equal(owner.address);
    });
  });

  describe("Listing", function () {
    it("Should list a token with traits", async function () {
      // Create traits for the NFT
      const traits = [
        { traitType: "Background", value: "Blue" },
        { traitType: "Eyes", value: "Green" },
      ];

      // Mint NFT with traits to user1
      await nftContract
        .connect(user1)
        .mintWithTraits(user1.address, "ipfs://tokenURI", traits);

      // Approve marketplace
      await nftContract
        .connect(user1)
        .setApprovalForAll(nftMarketplace.target, true);

      // List NFT with listing fee
      await nftMarketplace
        .connect(user1)
        .listNFT(nftContract.target, tokenId, price, { value: listingPrice });

      // Verify listing
      const marketItem = await nftMarketplace.getMarketItem(
        nftContract.target,
        tokenId
      );
      expect(marketItem.price).to.equal(price);
      expect(marketItem.seller).to.equal(user1.address);
      expect(marketItem.sold).to.be.false;

      // Verify traits are preserved
      const nftTraits = await nftContract.getTraits(tokenId);
      expect(nftTraits.length).to.equal(2);
      expect(nftTraits[0].traitType).to.equal("Background");
      expect(nftTraits[0].value).to.equal("Blue");
      expect(nftTraits[1].traitType).to.equal("Eyes");
      expect(nftTraits[1].value).to.equal("Green");
    });

    it("Should revert when listing price is zero", async function () {
      await expect(
        nftMarketplace.connect(user1).listNFT(nftContract.target, tokenId, 0)
      ).to.be.revertedWith("Price must be greater than 0");
    });

    it("Should revert when listing fee is not paid", async function () {
      await expect(
        nftMarketplace
          .connect(user1)
          .listNFT(nftContract.target, tokenId, price)
      ).to.be.revertedWith("Must pay listing fee");
    });

    it("Should revert when NFT is not approved", async function () {
      // Mint NFT to user1
      await nftContract
        .connect(user1)
        .mintWithTraits(user1.address, "ipfs://tokenURI", [
          { traitType: "Background", value: "Blue" },
        ]);

      // Don't approve marketplace
      await nftContract
        .connect(user1)
        .setApprovalForAll(nftMarketplace.target, false);

      // Try to list NFT without approval
      await expect(
        nftMarketplace
          .connect(user1)
          .listNFT(nftContract.target, tokenId, price, { value: listingPrice })
      ).to.be.revertedWith("NFT not approved for marketplace");
    });

    it("Should revert when NFT is not owned by the marketplace", async function () {
      // Mint NFT to user1
      await nftContract
        .connect(user1)
        .mintWithTraits(user1.address, "ipfs://tokenURI", [
          { traitType: "Background", value: "Blue" },
        ]);

      // Approve marketplace
      await nftContract
        .connect(user1)
        .setApprovalForAll(nftMarketplace.target, true);

      // List NFT (this will transfer ownership to marketplace)
      await nftMarketplace
        .connect(user1)
        .listNFT(nftContract.target, tokenId, price, { value: listingPrice });

      // Try to list the same NFT again (should fail because marketplace owns it)
      await expect(
        nftMarketplace
          .connect(user1)
          .listNFT(nftContract.target, tokenId, price, { value: listingPrice })
      ).to.be.revertedWith("Not token owner");
    });

    it("Should update listing price", async function () {
      const newListingPrice = ethers.parseEther("0.02");

      // Update listing price
      await nftMarketplace.connect(owner).updateListingPrice(newListingPrice);

      // Mint NFT to user1
      await nftContract
        .connect(user1)
        .mintWithTraits(user1.address, "ipfs://tokenURI", [
          { traitType: "Background", value: "Blue" },
        ]);

      // Approve marketplace
      await nftContract
        .connect(user1)
        .setApprovalForAll(nftMarketplace.target, true);

      // List NFT with new listing price
      await nftMarketplace
        .connect(user1)
        .listNFT(nftContract.target, tokenId, price, {
          value: newListingPrice,
        });

      // Verify listing was successful
      const marketItem = await nftMarketplace.getMarketItem(
        nftContract.target,
        tokenId
      );
      expect(marketItem.price).to.equal(price);
    });
  });

  describe("Offering", function () {
    beforeEach(async function () {
      // Mint and list an NFT for testing offers
      await mintAndListNFT(user1, tokenId, price, listingPrice);
    });

    it("Should make an offer for a listed NFT", async function () {
      const offerPrice = ethers.parseEther("0.8");
      const duration = 24 * 60 * 60; // 1 day in seconds

      // Make offer from user2
      await nftMarketplace
        .connect(user2)
        .makeOffer(nftContract.target, tokenId, duration, {
          value: offerPrice,
        });

      // Verify offer was created
      const [buyers, prices, expirations] = await nftMarketplace.getOffers(
        nftContract.target,
        tokenId
      );
      expect(buyers.length).to.equal(1);
      expect(buyers[0]).to.equal(user2.address);
      expect(prices[0]).to.equal(offerPrice);
      expect(expirations[0]).to.be.gt(0);
    });

    it("Should revert when making an offer with zero price", async function () {
      const duration = 24 * 60 * 60; // 1 day in seconds

      // Try to make offer with zero price
      await expect(
        nftMarketplace
          .connect(user2)
          .makeOffer(nftContract.target, tokenId, duration, { value: 0 })
      ).to.be.revertedWith("Offer price must be greater than 0");
    });

    it("Should revert when making an offer with invalid duration", async function () {
      const offerPrice = ethers.parseEther("0.8");
      const invalidDuration = 30 * 60; // 30 minutes (less than 1 hour)

      // Try to make offer with invalid duration
      await expect(
        nftMarketplace
          .connect(user2)
          .makeOffer(nftContract.target, tokenId, invalidDuration, {
            value: offerPrice,
          })
      ).to.be.revertedWith("Invalid duration");
    });

    it("Should revert when seller tries to make an offer", async function () {
      const offerPrice = ethers.parseEther("0.8");
      const duration = 24 * 60 * 60; // 1 day in seconds

      // Try to make offer as seller
      await expect(
        nftMarketplace
          .connect(user1)
          .makeOffer(nftContract.target, tokenId, duration, {
            value: offerPrice,
          })
      ).to.be.revertedWith("Seller cannot make offer");
    });

    it("Should accept an offer and transfer NFT", async function () {
      const offerPrice = ethers.parseEther("0.8");
      const duration = 24 * 60 * 60; // 1 day in seconds

      // Make offer from user2
      await nftMarketplace
        .connect(user2)
        .makeOffer(nftContract.target, tokenId, duration, {
          value: offerPrice,
        });

      // Accept offer
      await nftMarketplace
        .connect(user1)
        .acceptOffer(nftContract.target, tokenId, 0);

      // Verify NFT was transferred to user2
      expect(await nftContract.ownerOf(tokenId)).to.equal(user2.address);

      // Verify market item was updated
      const marketItem = await nftMarketplace.getMarketItem(
        nftContract.target,
        tokenId
      );
      expect(marketItem.sold).to.be.true;
      expect(marketItem.owner).to.equal(user2.address);
    });

    it("Should revert when non-seller tries to accept an offer", async function () {
      const offerPrice = ethers.parseEther("0.8");
      const duration = 24 * 60 * 60; // 1 day in seconds

      // Make offer from user2
      await nftMarketplace
        .connect(user2)
        .makeOffer(nftContract.target, tokenId, duration, {
          value: offerPrice,
        });

      // Try to accept offer as non-seller
      await expect(
        nftMarketplace
          .connect(user2)
          .acceptOffer(nftContract.target, tokenId, 0)
      ).to.be.revertedWith("Only seller can accept offer");
    });

    it("Should cancel an offer and refund the buyer", async function () {
      const offerPrice = ethers.parseEther("0.8");
      const duration = 24 * 60 * 60; // 1 day in seconds

      // Make offer from user2
      await nftMarketplace
        .connect(user2)
        .makeOffer(nftContract.target, tokenId, duration, {
          value: offerPrice,
        });

      // Get user2's balance before cancellation
      const balanceBefore = await ethers.provider.getBalance(user2.address);

      // Cancel offer
      await nftMarketplace
        .connect(user2)
        .cancelOffer(nftContract.target, tokenId, 0);

      // Get user2's balance after cancellation
      const balanceAfter = await ethers.provider.getBalance(user2.address);

      // Verify offer was cancelled (balance should be higher)
      expect(balanceAfter).to.be.gt(balanceBefore);

      // Verify offer is no longer active
      const [buyers] = await nftMarketplace.getOffers(
        nftContract.target,
        tokenId
      );
      expect(buyers.length).to.equal(0);
    });

    it("Should revert when non-buyer tries to cancel an offer", async function () {
      const offerPrice = ethers.parseEther("0.8");
      const duration = 24 * 60 * 60; // 1 day in seconds

      // Make offer from user2
      await nftMarketplace
        .connect(user2)
        .makeOffer(nftContract.target, tokenId, duration, {
          value: offerPrice,
        });

      // Try to cancel offer as non-buyer
      await expect(
        nftMarketplace
          .connect(user1)
          .cancelOffer(nftContract.target, tokenId, 0)
      ).to.be.revertedWith("Only offer maker can cancel");
    });
  });

  describe("Buying", function () {
    beforeEach(async function () {
      // Mint and list an NFT for testing purchases
      await mintAndListNFT(user1, tokenId, price, listingPrice);
    });

    it("Should purchase a listed NFT", async function () {
      // Get user1's balance before purchase
      const sellerBalanceBefore = await ethers.provider.getBalance(
        user1.address
      );

      // Purchase NFT from user2
      await nftMarketplace
        .connect(user2)
        .purchaseNFT(nftContract.target, tokenId, { value: price });

      // Verify NFT was transferred to user2
      expect(await nftContract.ownerOf(tokenId)).to.equal(user2.address);

      // Verify market item was updated
      const marketItem = await nftMarketplace.getMarketItem(
        nftContract.target,
        tokenId
      );
      expect(marketItem.sold).to.be.true;
      expect(marketItem.owner).to.equal(user2.address);

      // Verify seller received payment (accounting for gas costs)
      const sellerBalanceAfter = await ethers.provider.getBalance(
        user1.address
      );
      expect(sellerBalanceAfter).to.be.gt(sellerBalanceBefore);
    });

    it("Should revert when purchasing with incorrect price", async function () {
      const incorrectPrice = ethers.parseEther("0.5");

      // Try to purchase with incorrect price
      await expect(
        nftMarketplace
          .connect(user2)
          .purchaseNFT(nftContract.target, tokenId, { value: incorrectPrice })
      ).to.be.revertedWith("Incorrect price");
    });

    it("Should revert when purchasing an already sold NFT", async function () {
      // Purchase NFT from user2
      await nftMarketplace
        .connect(user2)
        .purchaseNFT(nftContract.target, tokenId, { value: price });

      // Try to purchase the same NFT from user3
      await expect(
        nftMarketplace
          .connect(user3)
          .purchaseNFT(nftContract.target, tokenId, { value: price })
      ).to.be.revertedWith("Item already sold");
    });

    it("Should handle royalties when purchasing an NFT", async function () {
      // Mint NFT to owner and capture the token ID
      const mintTx = await nftContract
        .connect(owner)
        .mintWithTraits(owner.address, "ipfs://test-uri", [
          { traitType: "Background", value: "Blue" },
        ]);

      // Wait for the transaction to be mined
      const receipt = await mintTx.wait();

      // Extract the token ID from the TokenMinted event
      const tokenMintedEvent = receipt.logs.find(
        (log) => log.fragment && log.fragment.name === "TokenMinted"
      );
      const actualTokenId = tokenMintedEvent
        ? tokenMintedEvent.args[1]
        : tokenId;

      // Verify ownership before setting royalty
      const tokenOwner = await nftContract.ownerOf(actualTokenId);
      expect(tokenOwner).to.equal(owner.address);

      // Set royalty before listing (when owner still owns the NFT)
      await nftContract.connect(owner).setTokenRoyalty(
        actualTokenId,
        owner.address,
        500 // 5% royalty
      );

      // Approve marketplace for all tokens (not just this one)
      await nftContract
        .connect(owner)
        .setApprovalForAll(nftMarketplace.target, true);

      // List NFT
      await nftMarketplace
        .connect(owner)
        .listNFT(nftContract.target, actualTokenId, price, {
          value: listingPrice,
        });

      // Get initial balances
      const initialSellerBalance = await ethers.provider.getBalance(
        owner.address
      );

      // Buy NFT
      await nftMarketplace
        .connect(user1)
        .purchaseNFT(nftContract.target, actualTokenId, { value: price });

      // Calculate expected amounts
      const royaltyAmount = (price * BigInt(500)) / BigInt(10000); // 5% of price
      const sellerAmount = price - royaltyAmount - listingPrice;

      // Check final balances
      const finalSellerBalance = await ethers.provider.getBalance(
        owner.address
      );

      // Verify balances (accounting for gas costs with approximate comparison)
      expect(finalSellerBalance).to.be.gt(
        initialSellerBalance + sellerAmount - ethers.parseEther("0.01")
      );
    });

    it("Should fetch market items correctly", async function () {
      // Purchase the NFT
      await nftMarketplace
        .connect(user2)
        .purchaseNFT(nftContract.target, tokenId, { value: price });

      // Mint and list another NFT
      const tokenId2 = 2;
      await mintAndListNFT(user1, tokenId2, price, listingPrice);

      // Fetch market items
      const marketItems = await nftMarketplace.fetchMarketItems();

      // Verify only unsold items are returned
      expect(marketItems.length).to.equal(1);
      expect(marketItems[0].tokenId).to.equal(tokenId2);
      expect(marketItems[0].sold).to.be.false;
    });

    it("Should fetch my listed NFTs correctly", async function () {
      // Purchase the NFT
      await nftMarketplace
        .connect(user2)
        .purchaseNFT(nftContract.target, tokenId, { value: price });

      // Mint and list another NFT
      const tokenId2 = 2;
      await mintAndListNFT(user1, tokenId2, price, listingPrice);

      // Fetch my listed NFTs
      const myListedNFTs = await nftMarketplace
        .connect(user1)
        .fetchMyListedNFTs();

      // Verify all items listed by user1 are returned (including sold ones)
      expect(myListedNFTs.length).to.equal(2);
      expect(myListedNFTs[0].tokenId).to.equal(tokenId);
      expect(myListedNFTs[0].sold).to.be.true;
      expect(myListedNFTs[1].tokenId).to.equal(tokenId2);
      expect(myListedNFTs[1].sold).to.be.false;
    });

    it("Should fetch my NFTs correctly", async function () {
      // Purchase the NFT
      await nftMarketplace
        .connect(user2)
        .purchaseNFT(nftContract.target, tokenId, { value: price });

      // Fetch my NFTs
      const myNFTs = await nftMarketplace.connect(user2).fetchMyNFTs();

      // Verify only NFTs owned by user2 are returned
      expect(myNFTs.length).to.equal(1);
      expect(myNFTs[0].tokenId).to.equal(tokenId);
      expect(myNFTs[0].owner).to.equal(user2.address);
    });
  });
});
