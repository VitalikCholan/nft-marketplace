// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721Royalty} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";

contract NFTMarketplace is Ownable, ReentrancyGuard {
    struct MarketItem {
        uint256 tokenId;
        address nftContract;
        address payable seller;
        address payable owner;
        uint256 price;
        bool sold;
    }

    struct Offer {
        address payable buyer;
        uint256 price;
        uint256 expiresAt;
        bool isActive;
    }

    uint256 private listingPrice = 0.01 ether;
    mapping(address => mapping(uint256 => MarketItem)) private idToMarketItem;
    mapping(address => mapping(uint256 => Offer[])) private tokenIdToOffers;
    
    event NFTListed(address nftContract, uint256 tokenId, address seller, uint256 price);
    event NFTSold(address nftContract, uint256 tokenId, address seller, address buyer, uint256 price);
    event OfferCreated(address nftContract, uint256 tokenId, address buyer, uint256 price, uint256 expiresAt);
    event OfferAccepted(address nftContract, uint256 tokenId, address buyer, uint256 price);
    event OfferCancelled(address nftContract, uint256 tokenId, address buyer);

    // Add these state variables at the contract level
    address[] private _allNFTContracts;
    mapping(address => uint256) private _tokenIds;

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Gets a market item
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to get
     */
    function getMarketItem(address nftContract, uint256 tokenId) 
        public 
        view 
        returns (MarketItem memory) 
    {
        return idToMarketItem[nftContract][tokenId];
    }

    // Add this function to track new NFT contracts
    function _addNFTContract(address nftContract) private {
        bool exists = false;
        for (uint i = 0; i < _allNFTContracts.length; i++) {
            if (_allNFTContracts[i] == nftContract) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            _allNFTContracts.push(nftContract);
        }
    }

    /**
     * @dev Lists an existing NFT on the marketplace
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param price Listing price in wei
     */
    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) public payable nonReentrant {
        require(price > 0, "Price must be greater than 0");
        require(msg.value == listingPrice, "Must pay listing fee");

        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(nft.isApprovedForAll(msg.sender, address(this)), "NFT not approved for marketplace");

        _addNFTContract(nftContract);
        if (tokenId >= _tokenIds[nftContract]) {
            _tokenIds[nftContract] = tokenId + 1;
        }

        idToMarketItem[nftContract][tokenId] = MarketItem(
            tokenId,
            nftContract,
            payable(msg.sender),
            payable(address(this)),
            price,
            false
        );

        nft.transferFrom(msg.sender, address(this), tokenId);
        
        emit NFTListed(nftContract, tokenId, msg.sender, price);
    }

    /**
     * @dev Makes an offer for a listed NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to make offer for
     * @param duration Duration the offer is valid for (in seconds)
     */
    function makeOffer(
        address nftContract,
        uint256 tokenId,
        uint256 duration
    ) public payable nonReentrant {
        require(msg.value > 0, "Offer price must be greater than 0");
        require(duration >= 1 hours && duration <= 7 days, "Invalid duration");
        
        MarketItem storage item = idToMarketItem[nftContract][tokenId];
        require(!item.sold, "Item already sold");
        require(msg.sender != item.seller, "Seller cannot make offer");

        Offer memory offer = Offer({
            buyer: payable(msg.sender),
            price: msg.value,
            expiresAt: block.timestamp + duration,
            isActive: true
        });

        tokenIdToOffers[nftContract][tokenId].push(offer);
        
        emit OfferCreated(nftContract, tokenId, msg.sender, msg.value, offer.expiresAt);
    }

    /**
     * @dev Accepts an offer for a listed NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the NFT
     * @param offerIndex Index of the offer to accept
     */
    function acceptOffer(
        address nftContract,
        uint256 tokenId,
        uint256 offerIndex
    ) public nonReentrant {
        MarketItem storage item = idToMarketItem[nftContract][tokenId];
        require(msg.sender == item.seller, "Only seller can accept offer");
        
        Offer[] storage offers = tokenIdToOffers[nftContract][tokenId];
        require(offerIndex < offers.length, "Invalid offer index");
        
        Offer storage offer = offers[offerIndex];
        require(offer.isActive, "Offer is not active");
        require(block.timestamp <= offer.expiresAt, "Offer expired");

        // Mark offer as accepted
        offer.isActive = false;
        item.sold = true;
        item.owner = offer.buyer;

        // Handle royalties using ERC721Royalty
        try ERC721Royalty(nftContract).royaltyInfo(tokenId, offer.price) returns (
            address receiver,
            uint256 royaltyAmount
        ) {
            if (royaltyAmount > 0 && receiver != address(0)) {
                payable(receiver).transfer(royaltyAmount);
                item.seller.transfer(offer.price - royaltyAmount);
            } else {
                item.seller.transfer(offer.price);
            }
        } catch {
            item.seller.transfer(offer.price);
        }

        // Transfer NFT to buyer
        IERC721(nftContract).transferFrom(address(this), offer.buyer, tokenId);
        
        // Refund other active offers
        for (uint i = 0; i < offers.length; i++) {
            if (i != offerIndex && offers[i].isActive && block.timestamp <= offers[i].expiresAt) {
                offers[i].isActive = false;
                offers[i].buyer.transfer(offers[i].price);
            }
        }

        emit OfferAccepted(nftContract, tokenId, offer.buyer, offer.price);
    }

    /**
     * @dev Cancels an active offer
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the NFT
     * @param offerIndex Index of the offer to cancel
     */
    function cancelOffer(
        address nftContract,
        uint256 tokenId,
        uint256 offerIndex
    ) public nonReentrant {
        Offer[] storage offers = tokenIdToOffers[nftContract][tokenId];
        require(offerIndex < offers.length, "Invalid offer index");
        
        Offer storage offer = offers[offerIndex];
        require(msg.sender == offer.buyer, "Only offer maker can cancel");
        require(offer.isActive, "Offer is not active");

        offer.isActive = false;
        offer.buyer.transfer(offer.price);

        emit OfferCancelled(nftContract, tokenId, msg.sender);
    }

    /**
     * @dev Gets all active offers for a token
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to check offers for
     */
    function getOffers(address nftContract, uint256 tokenId) 
        public 
        view 
        returns (
            address[] memory buyers,
            uint256[] memory prices,
            uint256[] memory expirations
        ) 
    {
        Offer[] storage offers = tokenIdToOffers[nftContract][tokenId];
        uint256 activeCount = 0;
        
        // Count active offers
        for (uint i = 0; i < offers.length; i++) {
            if (offers[i].isActive && block.timestamp <= offers[i].expiresAt) {
                activeCount++;
            }
        }
        
        buyers = new address[](activeCount);
        prices = new uint256[](activeCount);
        expirations = new uint256[](activeCount);
        
        uint256 index = 0;
        for (uint i = 0; i < offers.length; i++) {
            if (offers[i].isActive && block.timestamp <= offers[i].expiresAt) {
                buyers[index] = offers[i].buyer;
                prices[index] = offers[i].price;
                expirations[index] = offers[i].expiresAt;
                index++;
            }
        }
    }

    /**
     * @dev Purchases a listed NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to purchase
     */
    function purchaseNFT(
        address nftContract,
        uint256 tokenId
    ) public payable nonReentrant {
        MarketItem storage item = idToMarketItem[nftContract][tokenId];
        require(!item.sold, "Item already sold");
        require(msg.value == item.price, "Incorrect price");

        item.sold = true;
        item.owner = payable(msg.sender);

        // Try to handle as ERC721Royalty
        try ERC721Royalty(nftContract).royaltyInfo(tokenId, msg.value) returns (
            address receiver,
            uint256 royaltyAmount
        ) {
            if (royaltyAmount > 0 && receiver != address(0)) {
                payable(receiver).transfer(royaltyAmount);
                item.seller.transfer(msg.value - royaltyAmount);
            } else {
                item.seller.transfer(msg.value);
            }
        } catch {
            // If not ERC721Royalty, fallback to regular payment
            item.seller.transfer(msg.value);
        }

        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        payable(owner()).transfer(listingPrice);
        
        emit NFTSold(nftContract, tokenId, item.seller, msg.sender, msg.value);
    }

    /**
     * @dev Fetches all unsold market items
     * @return Array of MarketItem structs representing all unsold items
     */
    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint totalItemCount = 0;
        uint unsoldItemCount = 0;
        
        // First, count total items and unsold items
        for (uint i = 0; i < _allNFTContracts.length; i++) {
            address nftContract = _allNFTContracts[i];
            for (uint j = 0; j < _tokenIds[nftContract]; j++) {
                if (idToMarketItem[nftContract][j].nftContract != address(0)) {
                    totalItemCount++;
                    if (!idToMarketItem[nftContract][j].sold) {
                        unsoldItemCount++;
                    }
                }
            }
        }

        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        uint currentIndex = 0;

        // Then populate the array
        for (uint i = 0; i < _allNFTContracts.length; i++) {
            address nftContract = _allNFTContracts[i];
            for (uint j = 0; j < _tokenIds[nftContract]; j++) {
                if (idToMarketItem[nftContract][j].nftContract != address(0) && 
                    !idToMarketItem[nftContract][j].sold) {
                    MarketItem storage currentItem = idToMarketItem[nftContract][j];
                    items[currentIndex] = currentItem;
                    currentIndex++;
                }
            }
        }

        return items;
    }

    /**
     * @dev Fetches all NFTs listed by the caller
     * @return Array of MarketItem structs representing items listed by caller
     */
    function fetchMyListedNFTs() public view returns (MarketItem[] memory) {
        uint totalItemCount = 0;
        uint myItemCount = 0;
        
        // First, count items listed by caller
        for (uint i = 0; i < _allNFTContracts.length; i++) {
            address nftContract = _allNFTContracts[i];
            for (uint j = 0; j < _tokenIds[nftContract]; j++) {
                if (idToMarketItem[nftContract][j].seller == msg.sender) {
                    myItemCount++;
                }
                if (idToMarketItem[nftContract][j].nftContract != address(0)) {
                    totalItemCount++;
                }
            }
        }

        MarketItem[] memory items = new MarketItem[](myItemCount);
        uint currentIndex = 0;

        // Then populate the array
        for (uint i = 0; i < _allNFTContracts.length; i++) {
            address nftContract = _allNFTContracts[i];
            for (uint j = 0; j < _tokenIds[nftContract]; j++) {
                if (idToMarketItem[nftContract][j].seller == msg.sender) {
                    MarketItem storage currentItem = idToMarketItem[nftContract][j];
                    items[currentIndex] = currentItem;
                    currentIndex++;
                }
            }
        }

        return items;
    }

    /**
     * @dev Fetches all NFTs owned by the caller
     * @return Array of MarketItem structs representing owned items
     */
    function fetchMyNFTs() public view returns (MarketItem[] memory) {
        uint totalItemCount = 0;
        uint myItemCount = 0;
        
        // First, count items owned by caller
        for (uint i = 0; i < _allNFTContracts.length; i++) {
            address nftContract = _allNFTContracts[i];
            for (uint j = 0; j < _tokenIds[nftContract]; j++) {
                if (idToMarketItem[nftContract][j].owner == msg.sender) {
                    myItemCount++;
                }
                if (idToMarketItem[nftContract][j].nftContract != address(0)) {
                    totalItemCount++;
                }
            }
        }

        MarketItem[] memory items = new MarketItem[](myItemCount);
        uint currentIndex = 0;

        // Then populate the array
        for (uint i = 0; i < _allNFTContracts.length; i++) {
            address nftContract = _allNFTContracts[i];
            for (uint j = 0; j < _tokenIds[nftContract]; j++) {
                if (idToMarketItem[nftContract][j].owner == msg.sender) {
                    MarketItem storage currentItem = idToMarketItem[nftContract][j];
                    items[currentIndex] = currentItem;
                    currentIndex++;
                }
            }
        }

        return items;
    }

    /**
     * @dev Updates the listing price
     * @param _listingPrice New listing price in wei
     */
    function updateListingPrice(uint256 _listingPrice) public onlyOwner {
        listingPrice = _listingPrice;
    }
}

