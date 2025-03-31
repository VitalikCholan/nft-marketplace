// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

/**
 * @title NFTMarketplace
 * @dev Implementation of a marketplace for NFTs with royalty support
 * @notice This contract handles NFT minting, listing, sales, and royalty distributions
 * @author Vitalik Cholan 
 */

contract NFTMarketplace is ERC721URIStorage, ERC2981, Ownable, ReentrancyGuard {
    uint256 private _tokenIdCounter = 0;
    uint256 private _itemsSold = 0;
    
    uint256 private listingPrice = 0.01 ether;

    // Mapping from token ID to its creator
    mapping(uint256 => address) private _tokenCreators;
    
    mapping(uint256 => MarketItem) private idToMarketItem;

    struct MarketItem {
        uint256 tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        bool sold;
    }

    struct Auction {
        uint256 tokenId;
        address payable seller;
        uint256 startingPrice;
        uint256 endingPrice;
        uint256 duration;
        uint256 startedAt;
        bool isActive;
        address highestBidder;
        uint256 highestBid;
    }

    struct Offer {
        address payable buyer;
        uint256 price;
        uint256 expiresAt;
    }

    mapping(uint256 => Auction) private tokenIdToAuction;
    mapping(uint256 => Offer[]) private tokenIdToOffers;

    event MarketItemCreated(
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        bool sold
    );
    
    event MarketItemSold(
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        uint256 royaltyAmount
    );
    
    event RoyaltySet(
        uint256 indexed tokenId,
        address receiver,
        uint96 feeNumerator
    );

    event AuctionCreated(uint256 indexed tokenId, uint256 startingPrice, uint256 duration);
    event AuctionCancelled(uint256 indexed tokenId);
    event BidPlaced(uint256 indexed tokenId, address indexed bidder, uint256 bid);
    event AuctionFinalized(uint256 indexed tokenId, address winner, uint256 price);
    event OfferCreated(uint256 indexed tokenId, address indexed buyer, uint256 price);
    event OfferAccepted(uint256 indexed tokenId, address indexed buyer, uint256 price);

    constructor() ERC721("Metaverse Tokens", "METT") Ownable(msg.sender) {}

    // Override supportsInterface to support both ERC721 and ERC2981
    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /* Updates the listing price of the contract */
    function updateListingPrice(uint256 _listingPrice) public onlyOwner {
        listingPrice = _listingPrice;
    }

    /* Returns the listing price of the contract */
    function getListingPrice() public view returns (uint256) {
        return listingPrice;
    }

    /**
     * @dev Creates and lists a new token in the marketplace
     * @param tokenURI The metadata URI for the new token
     * @param price The listing price in wei
     * @param royaltyReceiver Address to receive royalties from future sales
     * @param royaltyFeeNumerator Royalty percentage in basis points (100 = 1%)
     * @return tokenId The ID of the newly created token
     * @notice Requires payment of listing fee
     * @notice Price must be greater than 0
     * @notice Royalty fee cannot exceed 10% (1000 basis points)
     */
    function createToken(
        string memory tokenURI, 
        uint256 price,
        address royaltyReceiver,
        uint96 royaltyFeeNumerator
    ) public payable nonReentrant returns (uint256) {
        require(price > 0, "Price must be at least 1 wei");
        require(msg.value == listingPrice, "Price must be equal to listing price");
        require(royaltyFeeNumerator <= 1000, "Royalty fee cannot exceed 10%"); // 10% = 1000 basis points

        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;

        _mint(msg.sender, tokenId);
        _setTokenURI(tokenId, tokenURI);
        
        // Set royalty information for this token
        _setTokenRoyalty(tokenId, royaltyReceiver, royaltyFeeNumerator);
        
        // Store the creator
        _tokenCreators[tokenId] = msg.sender;
        
        createMarketItem(tokenId, price);
        
        emit RoyaltySet(tokenId, royaltyReceiver, royaltyFeeNumerator);
        
        return tokenId;
    }

    function createMarketItem(uint256 tokenId, uint256 price) private {
        idToMarketItem[tokenId] = MarketItem(
            tokenId,
            payable(msg.sender),
            payable(address(this)),
            price,
            false
        );

        _transfer(msg.sender, address(this), tokenId);
        
        emit MarketItemCreated(
            tokenId,
            msg.sender,
            address(this),
            price,
            false
        );
    }

    /**
     * @dev Allows token owner to relist their token
     * @param tokenId The ID of the token to relist
     * @param price New listing price in wei
     * @notice Requires payment of listing fee
     * @notice Only the current owner can relist
     * @notice Token is transferred to marketplace contract during listing
     */
    function resellToken(uint256 tokenId, uint256 price) public payable nonReentrant {
        require(idToMarketItem[tokenId].owner == msg.sender, "Only item owner can perform this operation");
        require(msg.value == listingPrice, "Price must be equal to listing price");
        
        idToMarketItem[tokenId].sold = false;
        idToMarketItem[tokenId].price = price;
        idToMarketItem[tokenId].seller = payable(msg.sender);
        idToMarketItem[tokenId].owner = payable(address(this));
        
        _itemsSold--;

        _transfer(msg.sender, address(this), tokenId);
    }

    /**
     * @dev Executes the sale of a marketplace item
     * @param tokenId The ID of the token being purchased
     * @notice Requires full payment of the asking price
     * @notice Automatically distributes:
     *         - Listing fee to marketplace owner
     *         - Royalties to royalty receiver (if applicable)
     *         - Remaining amount to seller
     * @notice Updates ownership and marketplace state
     */
    function createMarketSale(uint256 tokenId) public payable nonReentrant {
        uint256 price = idToMarketItem[tokenId].price;
        address payable seller = idToMarketItem[tokenId].seller;
        
        require(msg.value == price, "Please submit the asking price in order to complete the purchase");
        require(idToMarketItem[tokenId].sold == false, "This item is already sold");
        
        // Update state first (checks-effects-interactions pattern)
        idToMarketItem[tokenId].owner = payable(msg.sender);
        idToMarketItem[tokenId].sold = true;
        idToMarketItem[tokenId].seller = payable(address(0));
        _itemsSold++;
        
        // Calculate and process royalties
        uint256 royaltyAmount = 0;
        address royaltyReceiver;
        
        (royaltyReceiver, royaltyAmount) = royaltyInfo(tokenId, price);
        
        // Then do transfers
        _transfer(address(this), msg.sender, tokenId);
        
        // Transfer marketplace fee to owner
        payable(owner()).transfer(listingPrice);
        
        // Transfer royalties if applicable
        if (royaltyAmount > 0 && royaltyReceiver != address(0)) {
            payable(royaltyReceiver).transfer(royaltyAmount);
            // Transfer remaining amount to the seller
            seller.transfer(price - royaltyAmount);
        } else {
            // If no royalties, transfer full amount to seller
            seller.transfer(price);
        }
        
        emit MarketItemSold(tokenId, seller, msg.sender, price, royaltyAmount);
    }
    
    /* Returns the creator of a token */
    function getTokenCreator(uint256 tokenId) public view returns (address) {
        require(ownerOf(tokenId) != address(0),"Token does not exist");
        return _tokenCreators[tokenId];
    }
    
    /**
     * @dev Updates royalty information for a token
     * @param tokenId The ID of the token
     * @param receiver New address to receive royalties
     * @param feeNumerator New royalty percentage in basis points
     * @notice Only the original creator can update royalties
     * @notice Fee cannot exceed 10% (1000 basis points)
     */
    function updateTokenRoyalty(
        uint256 tokenId, 
        address receiver, 
        uint96 feeNumerator
    ) public {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        require(_tokenCreators[tokenId] == msg.sender, "Only token creator can update royalties");
        require(feeNumerator <= 1000, "Royalty fee cannot exceed 10%"); // 10% = 1000 basis points
        
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
        emit RoyaltySet(tokenId, receiver, feeNumerator);
    }

    /**
     * @dev Fetches all unsold items in the marketplace
     * @return Array of MarketItem structs representing unsold items
     * @notice Only returns items that are currently listed and not sold
     */
    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIdCounter;
        uint256 unsoldItemCount = totalItemCount - _itemsSold;
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        
        for (uint256 i = 1; i <= totalItemCount; i++) {
            if (idToMarketItem[i].owner == address(this) && !idToMarketItem[i].sold) {
                MarketItem storage currentItem = idToMarketItem[i];
                items[currentIndex] = currentItem;
                currentIndex++;
            }
        }
        
        return items;
    }

    /**
     * @dev Fetches all NFTs owned by the caller
     * @return Array of MarketItem structs representing owned items
     * @notice Includes both listed and unlisted items owned by the caller
     */
    function fetchMyNFTs() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIdCounter;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        // Count the number of items owned by the user
        for (uint256 i = 1; i <= totalItemCount; i++) {
            if (idToMarketItem[i].owner == msg.sender) {
                itemCount++;
            }
        }

        // Create and populate the array
        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 1; i <= totalItemCount; i++) {
            if (idToMarketItem[i].owner == msg.sender) {
                MarketItem storage currentItem = idToMarketItem[i];
                items[currentIndex] = currentItem;
                currentIndex++;
            }
        }
        
        return items;
    }

    /**
     * @dev Fetches all items currently listed by the caller
     * @return Array of MarketItem structs representing listed items
     * @notice Only returns items that are currently listed and not sold
     */
    function fetchItemsListed() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIdCounter;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        // Count the number of items listed by the user
        for (uint256 i = 1; i <= totalItemCount; i++) {
            if (idToMarketItem[i].seller == msg.sender && !idToMarketItem[i].sold) {
                itemCount++;
            }
        }

        // Create and populate the array
        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 1; i <= totalItemCount; i++) {
            if (idToMarketItem[i].seller == msg.sender && !idToMarketItem[i].sold) {
                MarketItem storage currentItem = idToMarketItem[i];
                items[currentIndex] = currentItem;
                currentIndex++;
            }
        }
        
        return items;
    }
    
    /**
     * @dev Fetches all tokens created by a specific address
     * @param creator Address of the creator to query
     * @return Array of MarketItem structs representing created items
     * @notice Returns all items regardless of current ownership or listing status
     */
    function fetchTokensCreatedBy(address creator) public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIdCounter;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        // Count the number of items created by the user
        for (uint256 i = 1; i <= totalItemCount; i++) {
            if (_tokenCreators[i] == creator) {
                itemCount++;
            }
        }

        // Create and populate the array
        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 1; i <= totalItemCount; i++) {
            if (_tokenCreators[i] == creator) {
                MarketItem storage currentItem = idToMarketItem[i];
                items[currentIndex] = currentItem;
                currentIndex++;
            }
        }
        
        return items;
    }

    /**
     * @dev Emergency function to withdraw stuck funds
     * @notice Only callable by contract owner
     * @notice Transfers entire contract balance to owner
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev Creates an auction for a token
     * @param tokenId The ID of the token to auction
     * @param startingPrice Starting price in wei
     * @param duration Duration of the auction in seconds
     */
    function createAuction(
        uint256 tokenId,
        uint256 startingPrice,
        uint256 duration
    ) public nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(duration >= 1 hours && duration <= 7 days, "Invalid duration");
        require(startingPrice > 0, "Invalid starting price");
        
        _transfer(msg.sender, address(this), tokenId);
        
        tokenIdToAuction[tokenId] = Auction({
            tokenId: tokenId,
            seller: payable(msg.sender),
            startingPrice: startingPrice,
            endingPrice: startingPrice,
            duration: duration,
            startedAt: block.timestamp,
            isActive: true,
            highestBidder: address(0),
            highestBid: 0
        });
        
        emit AuctionCreated(tokenId, startingPrice, duration);
    }

    /**
     * @dev Places a bid on an active auction
     * @param tokenId The ID of the token being auctioned
     */
    function placeBid(uint256 tokenId) public payable nonReentrant {
        Auction storage auction = tokenIdToAuction[tokenId];
        require(auction.isActive, "Auction not active");
        require(block.timestamp < auction.startedAt + auction.duration, "Auction ended");
        require(msg.value > auction.highestBid, "Bid too low");
        
        address payable previousBidder = payable(auction.highestBidder);
        uint256 previousBid = auction.highestBid;
        
        // Update auction state
        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;
        
        // Refund previous bidder
        if (previousBidder != address(0)) {
            previousBidder.transfer(previousBid);
        }
        
        emit BidPlaced(tokenId, msg.sender, msg.value);
    }

    /**
     * @dev Finalizes an auction after its duration has passed
     * @param tokenId The ID of the token being auctioned
     */
    function finalizeAuction(uint256 tokenId) public nonReentrant {
        Auction storage auction = tokenIdToAuction[tokenId];
        require(auction.isActive, "Auction not active");
        require(block.timestamp >= auction.startedAt + auction.duration, "Auction still active");
        
        auction.isActive = false;
        
        if (auction.highestBidder != address(0)) {
            // Transfer token to winner
            _transfer(address(this), auction.highestBidder, tokenId);
            
            // Calculate and transfer royalties
            (address royaltyReceiver, uint256 royaltyAmount) = royaltyInfo(tokenId, auction.highestBid);
            if (royaltyAmount > 0 && royaltyReceiver != address(0)) {
                payable(royaltyReceiver).transfer(royaltyAmount);
                auction.seller.transfer(auction.highestBid - royaltyAmount);
            } else {
                auction.seller.transfer(auction.highestBid);
            }
            
            emit AuctionFinalized(tokenId, auction.highestBidder, auction.highestBid);
        } else {
            // No bids, return token to seller
            _transfer(address(this), auction.seller, tokenId);
        }
    }

    /**
     * @dev Creates an offer for a token
     * @param tokenId The ID of the token
     * @param duration Duration the offer is valid for, in seconds
     */
    function makeOffer(uint256 tokenId, uint256 duration) public payable {
        require(msg.value > 0, "Invalid offer amount");
        require(duration >= 1 hours && duration <= 7 days, "Invalid duration");
        
        Offer memory offer = Offer({
            buyer: payable(msg.sender),
            price: msg.value,
            expiresAt: block.timestamp + duration
        });
        
        tokenIdToOffers[tokenId].push(offer);
        emit OfferCreated(tokenId, msg.sender, msg.value);
    }

    /**
     * @dev Accepts an offer for a token
     * @param tokenId The ID of the token
     * @param offerIndex The index of the offer to accept
     */
    function acceptOffer(uint256 tokenId, uint256 offerIndex) public nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        
        Offer[] storage offers = tokenIdToOffers[tokenId];
        require(offerIndex < offers.length, "Invalid offer index");
        
        Offer memory offer = offers[offerIndex];
        require(block.timestamp <= offer.expiresAt, "Offer expired");
        
        // Transfer token to buyer
        _transfer(msg.sender, offer.buyer, tokenId);
        
        // Calculate and transfer royalties
        (address royaltyReceiver, uint256 royaltyAmount) = royaltyInfo(tokenId, offer.price);
        if (royaltyAmount > 0 && royaltyReceiver != address(0)) {
            payable(royaltyReceiver).transfer(royaltyAmount);
            payable(msg.sender).transfer(offer.price - royaltyAmount);
        } else {
            payable(msg.sender).transfer(offer.price);
        }
        
        // Remove accepted offer and refund others
        for (uint i = 0; i < offers.length; i++) {
            if (i != offerIndex && block.timestamp <= offers[i].expiresAt) {
                offers[i].buyer.transfer(offers[i].price);
            }
        }
        
        delete tokenIdToOffers[tokenId];
        emit OfferAccepted(tokenId, offer.buyer, offer.price);
    }
}