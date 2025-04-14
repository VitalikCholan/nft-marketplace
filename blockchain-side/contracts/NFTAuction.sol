// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC721Royalty} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

contract NFTAuction is Ownable, ReentrancyGuard, Pausable {
    struct Auction {
        uint256 tokenId;
        address nftContract;
        address payable seller;
        uint256 startingPrice;
        uint256 currentBid;
        address currentBidder;
        uint256 endTime;
        bool ended;
        uint256 commitPhaseEnd;
        uint256 revealPhaseEnd;
    }

    struct Commit {
        bytes32 commitment;
        uint256 amount;
        bool revealed;
    }

    mapping(address => mapping(uint256 => Auction)) public tokenIdToAuction;
    mapping(address => mapping(uint256 => mapping(address => Commit))) private bidCommitments;
    mapping(address => mapping(uint256 => mapping(address => uint256))) private pendingReturns;
    
    uint256 public auctionFee = 0.01 ether;
    uint256 public constant COMMIT_PHASE_DURATION = 1 days;
    uint256 public constant REVEAL_PHASE_DURATION = 1 days;

    constructor() Ownable(msg.sender) {}

    event AuctionCreated(address nftContract, uint256 tokenId, uint256 startingPrice, uint256 endTime);
    event BidCommitted(address nftContract, uint256 tokenId, address bidder, bytes32 commitment);
    event BidRevealed(address nftContract, uint256 tokenId, address bidder, uint256 amount);
    event AuctionEnded(address nftContract, uint256 tokenId, address winner, uint256 amount);
    event AuctionCancelled(address nftContract, uint256 tokenId);
    /**
     * @dev Creates a new auction for an NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to auction
     * @param startingPrice Starting price for the auction
     * @param duration Duration of the auction in seconds
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 duration
    ) public payable nonReentrant whenNotPaused {
        require(startingPrice > 0, "Starting price must be greater than 0");
        require(duration >= 1 hours && duration <= 7 days, "Duration must be between 1 hour and 7 days");
        require(msg.value == auctionFee, "Must pay auction fee");

        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(nft.isApprovedForAll(msg.sender, address(this)), "NFT not approved for marketplace");
        
        // Ensure token isn't already in an active auction
        require(!tokenIdToAuction[nftContract][tokenId].ended, "Auction already exists");

        // Transfer NFT to marketplace
        nft.transferFrom(msg.sender, address(this), tokenId);

        uint256 commitPhaseEnd = block.timestamp + COMMIT_PHASE_DURATION;
        uint256 revealPhaseEnd = commitPhaseEnd + REVEAL_PHASE_DURATION;
        uint256 auctionEnd = revealPhaseEnd + duration;

        // Create auction
        tokenIdToAuction[nftContract][tokenId] = Auction({
            tokenId: tokenId,
            nftContract: nftContract,
            seller: payable(msg.sender),
            startingPrice: startingPrice,
            currentBid: 0,
            currentBidder: address(0),
            endTime: auctionEnd,
            ended: false,
            commitPhaseEnd: commitPhaseEnd,
            revealPhaseEnd: revealPhaseEnd
        });

        emit AuctionCreated(nftContract, tokenId, startingPrice, auctionEnd);
    }

    /**
     * @dev Commits a bid for an auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the auction
     * @param commitment Hash of (bid amount + secret)
     */
    function commitBid(
        address nftContract,
        uint256 tokenId,
        bytes32 commitment
    ) public payable nonReentrant whenNotPaused {
        Auction storage auction = tokenIdToAuction[nftContract][tokenId];
        
        require(!auction.ended, "Auction already ended");
        require(block.timestamp < auction.commitPhaseEnd, "Commit phase ended");
        require(msg.value > 0, "Must send ETH with bid");
        
        // Store the commitment and the sent ETH
        bidCommitments[nftContract][tokenId][msg.sender] = Commit({
            commitment: commitment,
            amount: msg.value,
            revealed: false
        });

        emit BidCommitted(nftContract, tokenId, msg.sender, commitment);
    }

    /**
     * @dev Reveals a committed bid
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the auction
     * @param amount The actual bid amount
     * @param secret The secret used to create the commitment
     */
    function revealBid(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        bytes32 secret
    ) public nonReentrant whenNotPaused {
        Auction storage auction = tokenIdToAuction[nftContract][tokenId];
        Commit storage commit = bidCommitments[nftContract][tokenId][msg.sender];
        
        require(!auction.ended, "Auction already ended");
        require(block.timestamp >= auction.commitPhaseEnd, "Commit phase not ended");
        require(block.timestamp < auction.revealPhaseEnd, "Reveal phase ended");
        require(!commit.revealed, "Bid already revealed");
        require(commit.commitment == keccak256(abi.encodePacked(amount, secret)), "Invalid reveal");
        require(amount <= commit.amount, "Bid amount exceeds committed amount");

        // If this is the highest bid so far
        if (amount > auction.currentBid && amount >= auction.startingPrice) {
            // Refund the previous highest bidder if any
            if (auction.currentBidder != address(0)) {
                pendingReturns[nftContract][tokenId][auction.currentBidder] += auction.currentBid;
            }
            
            // Update auction state
            auction.currentBid = amount;
            auction.currentBidder = msg.sender;
        } else {
            // Refund the bidder
            pendingReturns[nftContract][tokenId][msg.sender] += amount;
        }

        // Mark the bid as revealed
        commit.revealed = true;

        emit BidRevealed(nftContract, tokenId, msg.sender, amount);
    }

    /**
     * @dev Ends an auction and transfers NFT to winner
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the auction
     */
    function endAuction(address nftContract, uint256 tokenId) public nonReentrant whenNotPaused {
        Auction storage auction = tokenIdToAuction[nftContract][tokenId];
        
        require(!auction.ended, "Auction already ended");
        require(block.timestamp >= auction.endTime, "Auction still active");

        auction.ended = true;
        
        if (auction.currentBidder != address(0)) {
            // Transfer NFT to winner
            IERC721(nftContract).transferFrom(address(this), auction.currentBidder, tokenId);
            
            // Handle royalties if supported
            if (IERC721(nftContract).supportsInterface(type(ERC721Royalty).interfaceId)) {
                (address royaltyReceiver, uint256 royaltyAmount) = ERC721Royalty(nftContract).royaltyInfo(tokenId, auction.currentBid);
                if (royaltyAmount > 0) {
                    payable(royaltyReceiver).transfer(royaltyAmount);
                    auction.seller.transfer(auction.currentBid - royaltyAmount);
                } else {
                    auction.seller.transfer(auction.currentBid);
                }
            } else {
                auction.seller.transfer(auction.currentBid);
            }

            emit AuctionEnded(nftContract, tokenId, auction.currentBidder, auction.currentBid);
        } else {
            // No bids, return NFT to seller
            IERC721(nftContract).transferFrom(address(this), auction.seller, tokenId);
            emit AuctionEnded(nftContract, tokenId, address(0), 0);
        }
    }

    /**
     * @dev Withdraws a refunded bid
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the auction
     */
    function withdrawBid(address nftContract, uint256 tokenId) public nonReentrant whenNotPaused {
        uint256 amount = pendingReturns[nftContract][tokenId][msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingReturns[nftContract][tokenId][msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    /**
     * @dev Cancels an auction if no bids have been placed
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the auction
     */
    function cancelAuction(address nftContract, uint256 tokenId) public nonReentrant whenNotPaused {
        Auction storage auction = tokenIdToAuction[nftContract][tokenId];
        
        require(!auction.ended, "Auction already ended");
        require(msg.sender == auction.seller, "Only seller can cancel");
        require(block.timestamp < auction.commitPhaseEnd, "Cannot cancel after commit phase");

        auction.ended = true;
        IERC721(nftContract).transferFrom(address(this), auction.seller, tokenId);
        
        emit AuctionCancelled(nftContract, tokenId);
    }

    /**
     * @dev Pauses all auction operations.
     * Can only be called by the owner.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses all auction operations.
     * Can only be called by the owner.
     */
    function unpause() public onlyOwner {
        _unpause();
    }
}