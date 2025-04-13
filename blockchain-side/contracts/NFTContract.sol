// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28; 

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Royalty} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title NFTContract
 * @notice This contract is a simple NFT contract that allows users to mint NFTs with traits
 * @author Vitalik Cholan 
 * @dev Implementation of the NFT contract with royalty support and traits
 */
contract NFTContract is ERC721URIStorage, ERC721Royalty, ERC721Enumerable, Ownable, Pausable {
    // Struct to define a trait
    struct Trait {
        string traitType;  // e.g., "Background", "Eyes", "Mouth"
        string value;      // e.g., "Blue", "Green", "Smile"
    }

    // Maximum number of traits per token
    uint256 public constant MAX_TRAITS = 8;
    
    // Token ID counter
    uint256 private _tokenIdCounter;
    
    // Base URI for token metadata
    string private _baseTokenURI;
    
    // Mapping from token ID to creator address
    mapping(uint256 => address) private _creators;

    // Mapping from token ID to its traits
    mapping(uint256 => Trait[]) private _tokenTraits;
    
    // Events
    event TokenMinted(address indexed creator, uint256 indexed tokenId, string tokenURI);
    event BaseURIUpdated(string newBaseURI);
    event RoyaltyUpdated(uint256 tokenId, address receiver, uint96 feeNumerator);
    event TraitsAdded(uint256 indexed tokenId, Trait[] traits);

    /**
     * @dev Constructor sets the name and symbol of the token
     * @param name_ Name of the token
     * @param symbol_ Symbol of the token
     */
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) Ownable(msg.sender) {}
    
      /**
     * @dev Mints a new token with traits
     * @param to Address to receive the token
     * @param metadataURI URI of the token metadata
     * @param traits Array of traits for the token
     * @return tokenId The ID of the newly minted token
     */
    function mintWithTraits(
        address to,
        string memory metadataURI,
        Trait[] memory traits
    ) public whenNotPaused returns (uint256) {
        require(bytes(metadataURI).length > 0, "Empty URI");

        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;
        
        _safeMint(to, newTokenId);
        _setTokenURI(newTokenId, metadataURI);
        _creators[newTokenId] = msg.sender;
        
        // Add traits
        for (uint i = 0; i < traits.length; i++) {
            _tokenTraits[newTokenId].push(traits[i]);
        }
        
        emit TokenMinted(msg.sender, newTokenId, metadataURI);
        emit TraitsAdded(newTokenId, traits);
        
        return newTokenId;
    }
    
    /**
     * @dev Sets the base URI for all token IDs
     * @param baseURI New base URI
     */
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
        emit BaseURIUpdated(baseURI);
    }
    
    /**
     * @dev Returns the base URI for all token IDs
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
    
    /**
     * @dev Sets the royalty information for a specific token ID
     * @param tokenId The ID of the token
     * @param receiver Address to receive the royalties
     * @param feeNumerator The royalty amount in basis points (1/10000)
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) public {
        require(_msgSender() == ownerOf(tokenId), "Caller is not the creator");
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
        emit RoyaltyUpdated(tokenId, receiver, feeNumerator);
    }

    /**
     * @dev Add or update traits for an existing token
     * @param tokenId The ID of the token
     * @param traits Array of traits to add/update
     */
    function setTraits(uint256 tokenId, Trait[] memory traits) public whenNotPaused {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        require(_msgSender() == ownerOf(tokenId), "Caller is not the token owner");
        require(traits.length <= MAX_TRAITS, "Too many traits"); // Add trait limit

        delete _tokenTraits[tokenId]; // Clear existing traits
        
        for (uint i = 0; i < traits.length; i++) {
            require(bytes(traits[i].traitType).length > 0, "Invalid trait type");
            require(bytes(traits[i].value).length > 0, "Invalid trait value");
            _tokenTraits[tokenId].push(traits[i]);
        }
        
        emit TraitsAdded(tokenId, traits);
    }
    
    /**
     * @dev Get all traits for a token
     * @param tokenId The ID of the token
     * @return Array of traits
     */
    function getTraits(uint256 tokenId) public view returns (Trait[] memory) {
        // Check if token exists in traits mapping 
        if (_tokenTraits[tokenId].length == 0 && _creators[tokenId] == address(0)) {
            return new Trait[](0);
        }
        return _tokenTraits[tokenId];
    }
    
    /**
     * @dev Returns the creator of a specific token
     * @param tokenId The ID of the token
     * @return The address of the creator
     */
    function getCreator(uint256 tokenId) public view returns (address) {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        return _creators[tokenId];
    }

    /**
     * @dev Required override for _update when using both ERC721Enumerable and ERC721Royalty
     */
    function _update(address to, uint256 tokenId, address auth) 
        internal 
        virtual 
        override(ERC721, ERC721Enumerable) 
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Required override for _increaseBalance when using both ERC721Enumerable and ERC721Royalty
     */
    function _increaseBalance(address account, uint128 amount) internal virtual override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, amount);
    }
    
    /**
     * @dev Override required by Solidity
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721URIStorage, ERC721Royalty, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
 * @dev Override the tokenURI function to resolve the conflict between
 * ERC721URIStorage and ERC721Royalty
 */
    function tokenURI(uint256 tokenId) public view override(ERC721URIStorage, ERC721) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Burns a token
     * @param tokenId The ID of the token to burn
     */
    function burn(uint256 tokenId) public whenNotPaused {
        require((ownerOf(tokenId) == _msgSender()) || (isApprovedForAll(ownerOf(tokenId), _msgSender())), "Caller is not owner nor approved");
        _burn(tokenId);
        delete _creators[tokenId];
        delete _tokenTraits[tokenId]; // Clean up traits data
    }

    /**
     * @dev Batch set traits for multiple tokens
     * @param tokenIds Array of token IDs
     * @param traitsArray Array of trait arrays for each token
     */
    function setTraitsBatch(
        uint256[] memory tokenIds,
        Trait[][] memory traitsArray
    ) public whenNotPaused {
        require(tokenIds.length == traitsArray.length, "Array lengths mismatch");
        
        for (uint i = 0; i < tokenIds.length; i++) {
            setTraits(tokenIds[i], traitsArray[i]);
        }
    }

    /**
     * @dev Batch mint multiple tokens with traits
     * @param to Address to receive the tokens
     * @param metadataURIs Array of token metadata URIs
     * @param traitsArray Array of trait arrays for each token
     * @return Array of minted token IDs
     */
    function mintWithTraitsBatch(
        address to,
        string[] memory metadataURIs,
        Trait[][] memory traitsArray
    ) public whenNotPaused returns (uint256[] memory) {
        require(metadataURIs.length == traitsArray.length, "Array lengths mismatch");
        
        uint256[] memory newTokenIds = new uint256[](metadataURIs.length);
        
        for (uint i = 0; i < metadataURIs.length; i++) {
            newTokenIds[i] = mintWithTraits(to, metadataURIs[i], traitsArray[i]);
        }
        
        return newTokenIds;
    }

    /**
     * @dev Pauses all token transfers, minting and burning.
     * Can only be called by the owner.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers, minting and burning.
     * Can only be called by the owner.
     */
    function unpause() public onlyOwner {
        _unpause();
    }
}