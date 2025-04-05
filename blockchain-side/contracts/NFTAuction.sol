// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC721Royalty} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";

contract NFTAuction is Ownable, ReentrancyGuard {
    struct Auction {
        uint256 tokenId;
        address nftContract;
        address payable seller;
        uint256 startingPrice;
        uint256 currentBid;
        address currentBidder;
        uint256 endTime;
        bool ended;
    }

    mapping(address => mapping(uint256 => Auction)) public tokenIdToAuction;
    mapping(address => mapping(uint256 => mapping(address => uint256))) private pendingReturns;
    
    uint256 public auctionFee = 0.01 ether;

    constructor() Ownable(msg.sender) {}

    event AuctionCreated(address nftContract, uint256 tokenId, uint256 startingPrice, uint256 endTime);
    event BidPlaced(address nftContract, uint256 tokenId, address bidder, uint256 amount);
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
    ) public payable nonReentrant {
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

        // Create auction
        tokenIdToAuction[nftContract][tokenId] = Auction({
            tokenId: tokenId,
            nftContract: nftContract,
            seller: payable(msg.sender),
            startingPrice: startingPrice,
            currentBid: 0,
            currentBidder: address(0),
            endTime: block.timestamp + duration,
            ended: false
        });

        emit AuctionCreated(nftContract, tokenId, startingPrice, block.timestamp + duration);
    }

    /**
     * @dev Places a bid on an active auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the auction
     */
    function placeBid(address nftContract, uint256 tokenId) public payable nonReentrant {
        Auction storage auction = tokenIdToAuction[nftContract][tokenId];
        
        require(!auction.ended, "Auction already ended");
        require(block.timestamp < auction.endTime, "Auction already ended");
        require(msg.value > auction.currentBid, "Bid not high enough");
        require(msg.value >= auction.startingPrice, "Bid below starting price");
        require(msg.sender != auction.seller, "Seller cannot bid");

        // If this is not the first bid, refund the previous bidder
        if (auction.currentBidder != address(0)) {
            pendingReturns[nftContract][tokenId][auction.currentBidder] += auction.currentBid;
        }

        // Update auction state
        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;

        emit BidPlaced(nftContract, tokenId, msg.sender, msg.value);
    }

    /**
     * @dev Ends an auction and transfers NFT to winner
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the auction
     */
    function endAuction(address nftContract, uint256 tokenId) public nonReentrant {
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
    function withdrawBid(address nftContract, uint256 tokenId) public nonReentrant {
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
    function cancelAuction(address nftContract, uint256 tokenId) public nonReentrant {
        Auction storage auction = tokenIdToAuction[nftContract][tokenId];
        
        require(!auction.ended, "Auction already ended");
        require(msg.sender == auction.seller, "Only seller can cancel");
        require(auction.currentBidder == address(0), "Cannot cancel auction with bids");

        auction.ended = true;
        IERC721(nftContract).transferFrom(address(this), auction.seller, tokenId);
        
        emit AuctionCancelled(nftContract, tokenId);
    }

}