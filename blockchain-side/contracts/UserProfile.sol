// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title UserProfile
 * @dev Contract for storing user profile data, preferences, and NFT connections
 */
contract UserProfile is Ownable {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Structs
    struct Profile {
        string username;
        string bio;
        string avatarURI;
        string coverURI;
        bool isVerified;
        uint256 createdAt;
        uint256 updatedAt;
        EnumerableSet.AddressSet favoriteNFTContracts;
        EnumerableSet.UintSet favoriteNFTs;
        mapping(string => string) customAttributes;
    }

    // State variables
    mapping(address => Profile) private profiles;
    mapping(string => address) private usernameToAddress;
    mapping(address => bool) private hasProfile;
    
    // Events
    event ProfileCreated(address indexed user, string username);
    event ProfileUpdated(address indexed user, string username);
    event AvatarUpdated(address indexed user, string avatarURI);
    event CoverUpdated(address indexed user, string coverURI);
    event BioUpdated(address indexed user, string bio);
    event FavoriteNFTAdded(address indexed user, address indexed nftContract, uint256 tokenId);
    event FavoriteNFTRemoved(address indexed user, address indexed nftContract, uint256 tokenId);
    event CustomAttributeSet(address indexed user, string key, string value);
    event CustomAttributeRemoved(address indexed user, string key);
    event ProfileVerified(address indexed user, bool isVerified);

    // Modifiers
    modifier onlyProfileOwner(address user) {
        require(msg.sender == user || msg.sender == owner(), "Not profile owner");
        _;
    }

    modifier profileExists(address user) {
        require(hasProfile[user], "Profile does not exist");
        _;
    }

    modifier usernameAvailable(string memory username) {
        require(usernameToAddress[username] == address(0), "Username already taken");
        _;
    }

    // Constructor
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Creates a new user profile
     * @param username The username for the profile
     * @param bio The user's biography
     * @param avatarURI URI to the user's avatar image
     * @param coverURI URI to the user's cover image
     */
    function createProfile(
        string memory username,
        string memory bio,
        string memory avatarURI,
        string memory coverURI
    ) external usernameAvailable(username) {
        require(!hasProfile[msg.sender], "Profile already exists");
        require(bytes(username).length >= 3, "Username too short");
        
        // Create new profile
        Profile storage profile = profiles[msg.sender];
        profile.username = username;
        profile.bio = bio;
        profile.avatarURI = avatarURI;
        profile.coverURI = coverURI;
        profile.isVerified = false;
        profile.createdAt = block.timestamp;
        profile.updatedAt = block.timestamp;
        
        // Set username mapping
        usernameToAddress[username] = msg.sender;
        hasProfile[msg.sender] = true;
        
        emit ProfileCreated(msg.sender, username);
    }

    /**
     * @dev Updates an existing user profile
     * @param bio The new biography
     * @param avatarURI URI to the new avatar image
     * @param coverURI URI to the new cover image
     */
    function updateProfile(
        string memory bio,
        string memory avatarURI,
        string memory coverURI
    ) external profileExists(msg.sender) onlyProfileOwner(msg.sender) {
        Profile storage profile = profiles[msg.sender];
        
        if (keccak256(bytes(profile.bio)) != keccak256(bytes(bio))) {
            profile.bio = bio;
            emit BioUpdated(msg.sender, bio);
        }
        
        if (keccak256(bytes(profile.avatarURI)) != keccak256(bytes(avatarURI))) {
            profile.avatarURI = avatarURI;
            emit AvatarUpdated(msg.sender, avatarURI);
        }
        
        if (keccak256(bytes(profile.coverURI)) != keccak256(bytes(coverURI))) {
            profile.coverURI = coverURI;
            emit CoverUpdated(msg.sender, coverURI);
        }
        
        profile.updatedAt = block.timestamp;
        emit ProfileUpdated(msg.sender, profile.username);
    }

    /**
     * @dev Updates the username of a profile
     * @param newUsername The new username
     */
    function updateUsername(string memory newUsername) 
        external 
        profileExists(msg.sender) 
        onlyProfileOwner(msg.sender)
        usernameAvailable(newUsername) 
    {
        Profile storage profile = profiles[msg.sender];
        string memory oldUsername = profile.username;
        
        // Update username mapping
        delete usernameToAddress[oldUsername];
        usernameToAddress[newUsername] = msg.sender;
        
        // Update profile
        profile.username = newUsername;
        profile.updatedAt = block.timestamp;
        
        emit ProfileUpdated(msg.sender, newUsername);
    }

    /**
     * @dev Adds an NFT to the user's favorites
     * @param nftContract The address of the NFT contract
     * @param tokenId The token ID of the NFT
     */
    function addFavoriteNFT(address nftContract, uint256 tokenId) 
        external 
        profileExists(msg.sender) 
        onlyProfileOwner(msg.sender) 
    {
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not NFT owner");
        
        Profile storage profile = profiles[msg.sender];
        
        // Add NFT contract to favorites if not already there
        if (!profile.favoriteNFTContracts.contains(nftContract)) {
            profile.favoriteNFTContracts.add(nftContract);
        }
        
        // Add NFT to favorites
        profile.favoriteNFTs.add(tokenId);
        
        emit FavoriteNFTAdded(msg.sender, nftContract, tokenId);
    }

    /**
     * @dev Removes an NFT from the user's favorites
     * @param nftContract The address of the NFT contract
     * @param tokenId The token ID of the NFT
     */
    function removeFavoriteNFT(address nftContract, uint256 tokenId) 
        external 
        profileExists(msg.sender) 
        onlyProfileOwner(msg.sender) 
    {
        Profile storage profile = profiles[msg.sender];
        
        // Remove NFT from favorites
        if (profile.favoriteNFTs.contains(tokenId)) {
            profile.favoriteNFTs.remove(tokenId);
            emit FavoriteNFTRemoved(msg.sender, nftContract, tokenId);
        }
        
        // Check if this was the last NFT from this contract
        bool hasOtherNFTsFromContract = false;
        for (uint256 i = 0; i < profile.favoriteNFTs.length(); i++) {
            uint256 favTokenId = profile.favoriteNFTs.at(i);
            if (IERC721(nftContract).ownerOf(favTokenId) == msg.sender) {
                hasOtherNFTsFromContract = true;
                break;
            }
        }
        
        // Remove contract from favorites if no other NFTs from this contract
        if (!hasOtherNFTsFromContract && profile.favoriteNFTContracts.contains(nftContract)) {
            profile.favoriteNFTContracts.remove(nftContract);
        }
    }

    /**
     * @dev Sets a custom attribute for the user's profile
     * @param key The attribute key
     * @param value The attribute value
     */
    function setCustomAttribute(string memory key, string memory value) 
        external 
        profileExists(msg.sender) 
        onlyProfileOwner(msg.sender) 
    {
        Profile storage profile = profiles[msg.sender];
        profile.customAttributes[key] = value;
        emit CustomAttributeSet(msg.sender, key, value);
    }

    /**
     * @dev Removes a custom attribute from the user's profile
     * @param key The attribute key to remove
     */
    function removeCustomAttribute(string memory key) 
        external 
        profileExists(msg.sender) 
        onlyProfileOwner(msg.sender) 
    {
        Profile storage profile = profiles[msg.sender];
        delete profile.customAttributes[key];
        emit CustomAttributeRemoved(msg.sender, key);
    }

    /**
     * @dev Sets the verification status of a profile (owner only)
     * @param user The address of the user
     * @param isVerified The verification status
     */
    function setVerificationStatus(address user, bool isVerified) 
        external 
        profileExists(user) 
    {
        require(msg.sender == user || msg.sender == owner(), "Not profile owner");
        Profile storage profile = profiles[user];
        profile.isVerified = isVerified;
        emit ProfileVerified(user, isVerified);
    }

    /**
     * @dev Gets the profile data for a user
     * @param user The address of the user
     * @return username The username
     * @return bio The biography
     * @return avatarURI The avatar URI
     * @return coverURI The cover URI
     * @return isVerified The verification status
     * @return createdAt The creation timestamp
     * @return updatedAt The last update timestamp
     */
    function getProfile(address user) 
        external 
        view 
        profileExists(user) 
        returns (
            string memory username,
            string memory bio,
            string memory avatarURI,
            string memory coverURI,
            bool isVerified,
            uint256 createdAt,
            uint256 updatedAt
        ) 
    {
        Profile storage profile = profiles[user];
        return (
            profile.username,
            profile.bio,
            profile.avatarURI,
            profile.coverURI,
            profile.isVerified,
            profile.createdAt,
            profile.updatedAt
        );
    }

    /**
     * @dev Gets the address associated with a username
     * @param username The username to look up
     * @return The address associated with the username
     */
    function getAddressByUsername(string memory username) 
        external 
        view 
        returns (address) 
    {
        return usernameToAddress[username];
    }

    /**
     * @dev Gets the favorite NFT contracts for a user
     * @param user The address of the user
     * @return An array of NFT contract addresses
     */
    function getFavoriteNFTContracts(address user) 
        external 
        view 
        profileExists(user) 
        returns (address[] memory) 
    {
        Profile storage profile = profiles[user];
        return profile.favoriteNFTContracts.values();
    }

    /**
     * @dev Gets the favorite NFTs for a user
     * @param user The address of the user
     * @return An array of token IDs
     */
    function getFavoriteNFTs(address user) 
        external 
        view 
        profileExists(user) 
        returns (uint256[] memory) 
    {
        Profile storage profile = profiles[user];
        return profile.favoriteNFTs.values();
    }

    /**
     * @dev Gets a custom attribute for a user
     * @param user The address of the user
     * @param key The attribute key
     * @return The attribute value
     */
    function getCustomAttribute(address user, string memory key) 
        external 
        view 
        profileExists(user) 
        returns (string memory) 
    {
        return profiles[user].customAttributes[key];
    }

    /**
     * @dev Checks if a user has a profile
     * @param user The address of the user
     * @return True if the user has a profile
     */
    function hasUserProfile(address user) 
        external 
        view 
        returns (bool) 
    {
        return hasProfile[user];
    }

    /**
     * @dev Gets all NFTs owned by a user from a specific contract
     * @param user The address of the user
     * @param nftContract The address of the NFT contract
     * @return An array of token IDs
     */
    function getOwnedNFTs(address user, address nftContract) 
        external 
        view 
        returns (uint256[] memory) 
    {
        // Check if the contract supports Enumerable extension
        try IERC721Enumerable(nftContract).balanceOf(user) returns (uint256 balance) {
            uint256[] memory tokenIds = new uint256[](balance);
            for (uint256 i = 0; i < balance; i++) {
                tokenIds[i] = IERC721Enumerable(nftContract).tokenOfOwnerByIndex(user, i);
            }
            return tokenIds;
        } catch {
            // If the contract doesn't support Enumerable, return an empty array
            return new uint256[](0);
        }
    }
} 