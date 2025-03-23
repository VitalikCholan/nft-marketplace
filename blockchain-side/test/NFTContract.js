const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");

describe("NFTContract", function () {
  // Fixture to deploy contract
  async function deployNFTContract() {
    const [owner, user1, user2] = await ethers.getSigners();
    const NFTContract = await ethers.deployContract("NFTContract", [
      "CoreNFT",
      "CNFT",
    ]);
    return { nftContract: NFTContract, owner, user1, user2 };
  }

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      const { nftContract, owner } = await loadFixture(deployNFTContract);
      expect(await nftContract.owner()).to.equal(owner.address);
    });

    it("Should set the correct name and symbol", async function () {
      const { nftContract } = await loadFixture(deployNFTContract);
      expect(await nftContract.name()).to.equal("CoreNFT");
      expect(await nftContract.symbol()).to.equal("CNFT");
    });
  });

  describe("Minting", function () {
    it("Should mint a new token with traits", async function () {
      const { nftContract, owner } = await loadFixture(deployNFTContract);
      const tokenURI = "ipfs://test";
      const traits = [
        { traitType: "Background", value: "Blue" },
        { traitType: "Eyes", value: "Green" },
      ];

      const tx = await nftContract.mintWithTraits(
        owner.address,
        tokenURI,
        traits
      );
      const receipt = await tx.wait();

      expect(await nftContract.ownerOf(1)).to.equal(owner.address);
      expect(await nftContract.tokenURI(1)).to.equal(tokenURI);

      const mintedTraits = await nftContract.getTraits(1);
      expect(mintedTraits.length).to.equal(2);
      expect(mintedTraits[0].traitType).to.equal("Background");
      expect(mintedTraits[0].value).to.equal("Blue");
    });

    it("Should emit TokenMinted event", async function () {
      const { nftContract, owner } = await loadFixture(deployNFTContract);
      const tokenURI = "ipfs://test";
      const traits = [{ traitType: "Background", value: "Blue" }];

      await expect(nftContract.mintWithTraits(owner.address, tokenURI, traits))
        .to.emit(nftContract, "TokenMinted")
        .withArgs(owner.address, 1, tokenURI);
    });
  });

  describe("Traits", function () {
    it("Should set and get traits correctly", async function () {
      const { nftContract, owner } = await loadFixture(deployNFTContract);

      // First mint a token
      await nftContract.mintWithTraits(owner.address, "ipfs://test", []);

      const traits = [
        { traitType: "Background", value: "Blue" },
        { traitType: "Eyes", value: "Green" },
      ];

      await nftContract.setTraits(1, traits);
      const retrievedTraits = await nftContract.getTraits(1);

      expect(retrievedTraits.length).to.equal(2);
      expect(retrievedTraits[0].traitType).to.equal("Background");
      expect(retrievedTraits[0].value).to.equal("Blue");
    });

    it("Should enforce trait limit", async function () {
      const { nftContract, owner } = await loadFixture(deployNFTContract);
      await nftContract.mintWithTraits(owner.address, "ipfs://test", []);

      const traits = Array(9).fill({ traitType: "Test", value: "Value" });

      await expect(nftContract.setTraits(1, traits)).to.be.revertedWith(
        "Too many traits"
      );
    });

    it("Should validate trait values", async function () {
      const { nftContract, owner } = await loadFixture(deployNFTContract);
      await nftContract.mintWithTraits(owner.address, "ipfs://test", []);

      const traits = [{ traitType: "", value: "Value" }];

      await expect(nftContract.setTraits(1, traits)).to.be.revertedWith(
        "Invalid trait type"
      );
    });
  });

  describe("Royalties", function () {
    it("Should set and get royalties correctly", async function () {
      const { nftContract, owner, user1 } = await loadFixture(
        deployNFTContract
      );
      await nftContract.mintWithTraits(owner.address, "ipfs://test", []);

      const royaltyReceiver = user1.address;
      const royaltyAmount = 500; // 5% (500 basis points)

      await nftContract.setTokenRoyalty(1, royaltyReceiver, royaltyAmount);

      const royaltyInfo = await nftContract.royaltyInfo(1, 10000); // 1 ETH
      expect(royaltyInfo[0]).to.equal(royaltyReceiver);
      expect(royaltyInfo[1]).to.equal(500); // 5% of 10000
    });

    it("Should only allow token owner to set royalties", async function () {
      const { nftContract, owner, user1 } = await loadFixture(
        deployNFTContract
      );
      await nftContract.mintWithTraits(owner.address, "ipfs://test", []);

      await expect(
        nftContract.connect(user1).setTokenRoyalty(1, user1.address, 500)
      ).to.be.revertedWith("Caller is not the creator");
    });
  });

  describe("Batch Operations", function () {
    it("Should mint multiple tokens with traits", async function () {
      const { nftContract, owner } = await loadFixture(deployNFTContract);

      const tokenURIs = ["ipfs://test1", "ipfs://test2"];
      const traitsArray = [
        [{ traitType: "Background", value: "Blue" }],
        [{ traitType: "Background", value: "Red" }],
      ];

      const tx = await nftContract.mintWithTraitsBatch(
        owner.address,
        tokenURIs,
        traitsArray
      );
      const receipt = await tx.wait();

      expect(await nftContract.ownerOf(1)).to.equal(owner.address);
      expect(await nftContract.tokenURI(1)).to.equal(tokenURIs[0]);
      expect(await nftContract.ownerOf(2)).to.equal(owner.address);
      expect(await nftContract.tokenURI(2)).to.equal(tokenURIs[1]);

      const mintedTraits = await nftContract.getTraits(1);
      expect(mintedTraits.length).to.equal(1);
      expect(mintedTraits[0].traitType).to.equal("Background");
      expect(mintedTraits[0].value).to.equal("Blue");

      const mintedTraits2 = await nftContract.getTraits(2);
      expect(mintedTraits2.length).to.equal(1);
      expect(mintedTraits2[0].traitType).to.equal("Background");
      expect(mintedTraits2[0].value).to.equal("Red");
    });

    it("Should revert if array lengths don't match", async function () {
      const { nftContract, owner } = await loadFixture(deployNFTContract);

      const tokenURIs = ["ipfs://test1", "ipfs://test2"];
      const traitsArray = [[{ traitType: "Background", value: "Blue" }]];

      await expect(
        nftContract.mintWithTraitsBatch(owner.address, tokenURIs, traitsArray)
      ).to.be.revertedWith("Array lengths mismatch");
    });
  });

  describe("Burning", function () {
    it("Should burn token and clean up data", async function () {
      const { nftContract, owner } = await loadFixture(deployNFTContract);

      // Mint a token with traits
      await nftContract.mintWithTraits(owner.address, "ipfs://test", [
        { traitType: "Background", value: "Blue" },
      ]);

      await nftContract.burn(1);

      await expect(nftContract.ownerOf(1)).to.be.reverted;
      const traits = await nftContract.getTraits(1);
      expect(traits.length).to.equal(0);
    });

    it("Should only allow owner or approved to burn", async function () {
      const { nftContract, owner, user1 } = await loadFixture(
        deployNFTContract
      );
      await nftContract.mintWithTraits(owner.address, "ipfs://test", []);

      await expect(nftContract.connect(user1).burn(1)).to.be.revertedWith(
        "Caller is not owner nor approved"
      );
    });
  });
});
