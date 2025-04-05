const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NFTAuction", function () {
  // Global variables
  let nftContract;
  let nftAuction;
  let owner;
  let user1;
  let user2;
  let user3;
  let tokenId;
  let tokenURI;
  let traits;
  let startingPrice;
  let duration;
  let auctionFee;

  // Setup function
  async function deployContracts() {
    const [ownerSigner, user1Signer, user2Signer, user3Signer] =
      await ethers.getSigners();

    // Deploy NFT contract
    const NFTContract = await ethers.getContractFactory("NFTContract");
    const nftContractInstance = await NFTContract.deploy("MyNFT", "MNFT");
    await nftContractInstance.waitForDeployment();

    // Deploy auction contract
    const NFTAuction = await ethers.getContractFactory("NFTAuction");
    const nftAuctionInstance = await NFTAuction.deploy();
    await nftAuctionInstance.waitForDeployment();

    return {
      nftContract: nftContractInstance,
      nftAuction: nftAuctionInstance,
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
    nftContract = contracts.nftContract;
    nftAuction = contracts.nftAuction;
    owner = contracts.owner;
    user1 = contracts.user1;
    user2 = contracts.user2;
    user3 = contracts.user3;

    // Set common test variables
    tokenURI = "ipfs://test-uri";
    traits = []; // Empty traits array
    tokenId = 1;
    startingPrice = ethers.parseEther("0.1");
    duration = 86400; // 1 day
    auctionFee = ethers.parseEther("0.01");

    // Mint NFT to user1
    await nftContract
      .connect(user1)
      .mintWithTraits(user1.address, tokenURI, traits);

    // Approve auction contract
    await nftContract.connect(user1).setApprovalForAll(nftAuction.target, true);
  });

  describe("Deployment", function () {
    it("Should deploy the contract", async function () {
      expect(await nftAuction.owner()).to.equal(owner.address);
    });

    it("Should set the correct auction fee", async function () {
      expect(await nftAuction.auctionFee()).to.equal(ethers.parseEther("0.01"));
    });
  });

  describe("Auction Creation", function () {
    it("Should create an auction successfully", async function () {
      const tx = await nftAuction
        .connect(user1)
        .createAuction(nftContract.target, tokenId, startingPrice, duration, {
          value: auctionFee,
        });

      const receipt = await tx.wait();

      // Find the AuctionCreated event
      const event = receipt.logs.find(
        (log) => log.fragment && log.fragment.name === "AuctionCreated"
      );

      // Extract the endTime from the actual event
      const actualEndTime = event.args[3];

      // Verify the auction was created with the correct parameters
      await expect(tx)
        .to.emit(nftAuction, "AuctionCreated")
        .withArgs(nftContract.target, tokenId, startingPrice, actualEndTime);

      // Verify auction details
      const auction = await nftAuction.tokenIdToAuction(
        nftContract.target,
        tokenId
      );
      expect(auction.tokenId).to.equal(tokenId);
      expect(auction.nftContract).to.equal(nftContract.target);
      expect(auction.seller).to.equal(user1.address);
      expect(auction.startingPrice).to.equal(startingPrice);
      expect(auction.currentBid).to.equal(0);
      expect(auction.currentBidder).to.equal(ethers.ZeroAddress);
      expect(auction.ended).to.equal(false);
    });

    it("Should fail to create auction with zero starting price", async function () {
      await expect(
        nftAuction
          .connect(user1)
          .createAuction(nftContract.target, tokenId, 0, duration, {
            value: auctionFee,
          })
      ).to.be.revertedWith("Starting price must be greater than 0");
    });

    it("Should fail to create auction with invalid duration", async function () {
      // Duration less than 1 hour
      await expect(
        nftAuction.connect(user1).createAuction(
          nftContract.target,
          tokenId,
          startingPrice,
          3599, // 59 minutes 59 seconds
          { value: auctionFee }
        )
      ).to.be.revertedWith("Duration must be between 1 hour and 7 days");

      // Duration more than 7 days
      await expect(
        nftAuction.connect(user1).createAuction(
          nftContract.target,
          tokenId,
          startingPrice,
          604801, // 7 days 1 second
          { value: auctionFee }
        )
      ).to.be.revertedWith("Duration must be between 1 hour and 7 days");
    });

    it("Should fail to create auction without paying fee", async function () {
      await expect(
        nftAuction
          .connect(user1)
          .createAuction(nftContract.target, tokenId, startingPrice, duration, {
            value: 0,
          })
      ).to.be.revertedWith("Must pay auction fee");
    });
  });

  describe("Bidding", function () {
    beforeEach(async function () {
      // Create auction for bidding tests
      await nftAuction
        .connect(user1)
        .createAuction(nftContract.target, tokenId, startingPrice, duration, {
          value: auctionFee,
        });
    });

    it("Should place a bid successfully", async function () {
      const bidAmount = ethers.parseEther("0.2");

      await expect(
        nftAuction
          .connect(user2)
          .placeBid(nftContract.target, tokenId, { value: bidAmount })
      )
        .to.emit(nftAuction, "BidPlaced")
        .withArgs(nftContract.target, tokenId, user2.address, bidAmount);

      // Verify auction state
      const auction = await nftAuction.tokenIdToAuction(
        nftContract.target,
        tokenId
      );
      expect(auction.currentBid).to.equal(bidAmount);
      expect(auction.currentBidder).to.equal(user2.address);
    });

    it("Should fail to place bid below starting price", async function () {
      const bidAmount = ethers.parseEther("0.05");

      await expect(
        nftAuction
          .connect(user2)
          .placeBid(nftContract.target, tokenId, { value: bidAmount })
      ).to.be.revertedWith("Bid below starting price");
    });

    it("Should fail if seller tries to bid", async function () {
      const bidAmount = ethers.parseEther("0.2");

      await expect(
        nftAuction
          .connect(user1)
          .placeBid(nftContract.target, tokenId, { value: bidAmount })
      ).to.be.revertedWith("Seller cannot bid");
    });
  });

  describe("Auction Ending", function () {
    it("Should end auction successfully with winner", async function () {
      // Create auction with short duration
      const duration = 3600; // 1 hour
      await nftAuction
        .connect(user1)
        .createAuction(nftContract.target, tokenId, startingPrice, duration, {
          value: auctionFee,
        });

      // Place bid
      const bidAmount = ethers.parseEther("0.2");
      await nftAuction
        .connect(user2)
        .placeBid(nftContract.target, tokenId, { value: bidAmount });

      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [duration]);
      await ethers.provider.send("evm_mine");

      // End auction
      await expect(nftAuction.endAuction(nftContract.target, tokenId))
        .to.emit(nftAuction, "AuctionEnded")
        .withArgs(nftContract.target, tokenId, user2.address, bidAmount);

      // Verify NFT ownership
      expect(await nftContract.ownerOf(tokenId)).to.equal(user2.address);
    });

    it("Should end auction with no bids and return NFT to seller", async function () {
      // Create auction with short duration
      const duration = 3600; // 1 hour
      await nftAuction
        .connect(user1)
        .createAuction(nftContract.target, tokenId, startingPrice, duration, {
          value: auctionFee,
        });

      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [duration]);
      await ethers.provider.send("evm_mine");

      // End auction
      await expect(nftAuction.endAuction(nftContract.target, tokenId))
        .to.emit(nftAuction, "AuctionEnded")
        .withArgs(nftContract.target, tokenId, ethers.ZeroAddress, 0);

      // Verify NFT ownership
      expect(await nftContract.ownerOf(tokenId)).to.equal(user1.address);
    });
  });

  describe("Auction Cancellation", function () {
    beforeEach(async function () {
      // Create auction for cancellation tests
      await nftAuction
        .connect(user1)
        .createAuction(nftContract.target, tokenId, startingPrice, duration, {
          value: auctionFee,
        });
    });

    it("Should cancel auction successfully", async function () {
      await expect(
        nftAuction.connect(user1).cancelAuction(nftContract.target, tokenId)
      )
        .to.emit(nftAuction, "AuctionCancelled")
        .withArgs(nftContract.target, tokenId);

      // Verify NFT ownership
      expect(await nftContract.ownerOf(tokenId)).to.equal(user1.address);
    });

    it("Should fail to cancel auction if not seller", async function () {
      await expect(
        nftAuction.connect(user2).cancelAuction(nftContract.target, tokenId)
      ).to.be.revertedWith("Only seller can cancel");
    });
  });

  describe("Bid Withdrawal", function () {
    it("Should withdraw bid successfully", async function () {
      // Create auction
      await nftAuction
        .connect(user1)
        .createAuction(nftContract.target, tokenId, startingPrice, duration, {
          value: auctionFee,
        });

      // Place first bid
      const firstBidAmount = ethers.parseEther("0.2");
      await nftAuction
        .connect(user2)
        .placeBid(nftContract.target, tokenId, { value: firstBidAmount });

      // Place second bid
      const secondBidAmount = ethers.parseEther("0.3");
      await nftAuction
        .connect(user3)
        .placeBid(nftContract.target, tokenId, { value: secondBidAmount });

      // Get initial balance
      const initialBalance = await ethers.provider.getBalance(user2.address);

      // Withdraw bid
      const withdrawTx = await nftAuction
        .connect(user2)
        .withdrawBid(nftContract.target, tokenId);
      const receipt = await withdrawTx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;

      // Check balance after withdrawal
      const finalBalance = await ethers.provider.getBalance(user2.address);
      expect(finalBalance).to.equal(initialBalance + firstBidAmount - gasUsed);
    });
  });
});
