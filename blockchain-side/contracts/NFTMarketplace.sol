// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC721Royalty} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";

contract NFTMarketplace is Ownable, ReentrancyGuard {
    struct MarketItem {
        uint256 tokenId;
        address nftContract;
        address payable seller;
        address owner;
        uint256 price;
        bool sold;
    }

    struct Offer {
        address buyer;
        uint256 price;
        uint256 expiration;
    }

    // Listing fee
    uint256 public listingPrice = 0.01 ether;
    
    // Mappings
    mapping(address => mapping(uint256 => MarketItem)) private idToMarketItem;
    mapping(address => mapping(uint256 => Offer[])) private tokenIdToOffers;

    // Add these tracking variables
    address[] private _allNFTContracts;
    mapping(address => uint256) private _tokenIds;
    mapping(address => bool) private _nftContractExists;

    // Events
    event MarketItemCreated(
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price
    );
    event MarketItemSold(
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price
    );
    event OfferCreated(
        address indexed nftContract,
        uint256 indexed tokenId,
        address buyer,
        uint256 price,
        uint256 expiration
    );
    event OfferAccepted(
        address indexed nftContract,
        uint256 indexed tokenId,
        address buyer,
        uint256 price
    );
    event OfferCancelled(
        address indexed nftContract,
        uint256 indexed tokenId,
        address buyer
    );

    constructor() Ownable(msg.sender) {}

    function updateListingPrice(uint256 _listingPrice) public onlyOwner {
        listingPrice = _listingPrice;
    }

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

        idToMarketItem[nftContract][tokenId] = MarketItem(
            tokenId,
            nftContract,
            payable(msg.sender),
            address(0),
            price,
            false
        );

        nft.transferFrom(msg.sender, address(this), tokenId);

        // Add this to your listNFT function
        if (!_nftContractExists[nftContract]) {
            _allNFTContracts.push(nftContract);
            _nftContractExists[nftContract] = true;
        }
        _tokenIds[nftContract] = _tokenIds[nftContract] > tokenId ? _tokenIds[nftContract] : tokenId + 1;

        emit MarketItemCreated(
            nftContract,
            tokenId,
            msg.sender,
            address(0),
            price
        );
    }

    function makeOffer(
        address nftContract,
        uint256 tokenId,
        uint256 duration
    ) public payable nonReentrant {
        require(msg.value > 0, "Offer price must be greater than 0");
        require(duration >= 1 hours, "Invalid duration");
        
        MarketItem storage item = idToMarketItem[nftContract][tokenId];
        require(msg.sender != item.seller, "Seller cannot make offer");

        tokenIdToOffers[nftContract][tokenId].push(
            Offer(msg.sender, msg.value, block.timestamp + duration)
        );

        emit OfferCreated(
            nftContract,
            tokenId,
            msg.sender,
            msg.value,
            block.timestamp + duration
        );
    }

    function acceptOffer(
        address nftContract,
        uint256 tokenId,
        uint256 offerIndex
    ) public nonReentrant {
        MarketItem storage item = idToMarketItem[nftContract][tokenId];
        require(msg.sender == item.seller, "Only seller can accept offer");

        Offer[] storage offers = tokenIdToOffers[nftContract][tokenId];
        require(offerIndex < offers.length, "Invalid offer index");
        require(block.timestamp <= offers[offerIndex].expiration, "Offer expired");

        Offer memory offer = offers[offerIndex];
        item.owner = offer.buyer;
        item.sold = true;

        IERC721 nft = IERC721(nftContract);
        
        // Handle royalties if supported
        if (IERC721(nftContract).supportsInterface(type(ERC721Royalty).interfaceId)) {
            (address royaltyReceiver, uint256 royaltyAmount) = ERC721Royalty(nftContract).royaltyInfo(tokenId, offer.price);
            if (royaltyAmount > 0) {
                payable(royaltyReceiver).transfer(royaltyAmount);
                item.seller.transfer(offer.price - royaltyAmount - listingPrice);
            } else {
                item.seller.transfer(offer.price - listingPrice);
            }
        } else {
            item.seller.transfer(offer.price - listingPrice);
        }

        nft.transferFrom(address(this), offer.buyer, tokenId);

        // Clear all offers
        delete tokenIdToOffers[nftContract][tokenId];

        emit MarketItemSold(
            nftContract,
            tokenId,
            item.seller,
            offer.buyer,
            offer.price
        );
    }

    function cancelOffer(
        address nftContract,
        uint256 tokenId,
        uint256 offerIndex
    ) public nonReentrant {
        Offer[] storage offers = tokenIdToOffers[nftContract][tokenId];
        require(offerIndex < offers.length, "Invalid offer index");
        require(msg.sender == offers[offerIndex].buyer, "Only offer maker can cancel");

        uint256 offerAmount = offers[offerIndex].price;
        
        // Remove offer
        offers[offerIndex] = offers[offers.length - 1];
        offers.pop();

        // Refund the offer amount
        payable(msg.sender).transfer(offerAmount);

        emit OfferCancelled(nftContract, tokenId, msg.sender);
    }

    function purchaseNFT(
        address nftContract,
        uint256 tokenId
    ) public payable nonReentrant {
        MarketItem storage item = idToMarketItem[nftContract][tokenId];
        require(!item.sold, "Item already sold");
        require(msg.value == item.price, "Incorrect price");

        item.owner = msg.sender;
        item.sold = true;

        IERC721 nft = IERC721(nftContract);

        // Handle royalties if supported
        if (IERC721(nftContract).supportsInterface(type(ERC721Royalty).interfaceId)) {
            (address royaltyReceiver, uint256 royaltyAmount) = ERC721Royalty(nftContract).royaltyInfo(tokenId, msg.value);
            if (royaltyAmount > 0) {
                payable(royaltyReceiver).transfer(royaltyAmount);
                item.seller.transfer(msg.value - royaltyAmount - listingPrice);
            } else {
                item.seller.transfer(msg.value - listingPrice);
            }
        } else {
            item.seller.transfer(msg.value - listingPrice);
        }

        nft.transferFrom(address(this), msg.sender, tokenId);

        // Clear any existing offers
        delete tokenIdToOffers[nftContract][tokenId];

        emit MarketItemSold(
            nftContract,
            tokenId,
            item.seller,
            msg.sender,
            msg.value
        );
    }

    function getMarketItem(address nftContract, uint256 tokenId)
        public
        view
        returns (MarketItem memory)
    {
        return idToMarketItem[nftContract][tokenId];
    }

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
        uint256 length = offers.length;

        buyers = new address[](length);
        prices = new uint256[](length);
        expirations = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            buyers[i] = offers[i].buyer;
            prices[i] = offers[i].price;
            expirations[i] = offers[i].expiration;
        }

        return (buyers, prices, expirations);
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
}