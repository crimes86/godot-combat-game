// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AchievementToken
 * @dev NFT contract for verified gaming achievements
 *
 * Key features:
 * - Only the backend (owner) can mint - ensures achievements are verified
 * - Each token stores the original earner's address (provenance)
 * - Achievements are freely tradeable (unlike soulbound)
 * - Metadata URI points to your API for dynamic achievement data
 */
contract AchievementToken is ERC721, ERC721URIStorage, Ownable {
    uint256 private _nextTokenId;

    // Achievement provenance - who originally earned it
    struct AchievementData {
        address originalEarner;     // Who actually earned the achievement
        string achievementId;       // Your internal achievement ID (e.g., "steam_440_tf2_hat")
        string provider;            // "steam", "battlenet", etc.
        uint256 mintedAt;           // Timestamp of mint
        string rarityTier;          // "Legendary", "Epic", etc.
    }

    // Token ID => Achievement data
    mapping(uint256 => AchievementData) public achievements;

    // Prevent duplicate mints: hash(wallet + achievementId) => minted
    mapping(bytes32 => bool) public alreadyMinted;

    // Events for indexing
    event AchievementMinted(
        uint256 indexed tokenId,
        address indexed originalEarner,
        string achievementId,
        string provider,
        string rarityTier
    );

    constructor() ERC721("Mantle Achievement", "ACHIEVE") Ownable(msg.sender) {}

    /**
     * @dev Mint a new achievement NFT. Only callable by backend (owner).
     * @param to Wallet address to mint to (the player who earned it)
     * @param achievementId Your internal achievement ID
     * @param provider Provider name (steam, battlenet, etc.)
     * @param rarityTier Rarity tier string
     * @param metadataUri URI pointing to achievement metadata JSON
     */
    function mintAchievement(
        address to,
        string memory achievementId,
        string memory provider,
        string memory rarityTier,
        string memory metadataUri
    ) public onlyOwner returns (uint256) {
        // Prevent duplicate mints for same wallet + achievement
        bytes32 mintHash = keccak256(abi.encodePacked(to, achievementId));
        require(!alreadyMinted[mintHash], "Achievement already minted for this wallet");
        alreadyMinted[mintHash] = true;

        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, metadataUri);

        achievements[tokenId] = AchievementData({
            originalEarner: to,
            achievementId: achievementId,
            provider: provider,
            mintedAt: block.timestamp,
            rarityTier: rarityTier
        });

        emit AchievementMinted(tokenId, to, achievementId, provider, rarityTier);

        return tokenId;
    }

    /**
     * @dev Batch mint multiple achievements (gas efficient)
     */
    function batchMintAchievements(
        address to,
        string[] memory achievementIds,
        string[] memory providers,
        string[] memory rarityTiers,
        string[] memory metadataUris
    ) public onlyOwner returns (uint256[] memory) {
        require(
            achievementIds.length == providers.length &&
            providers.length == rarityTiers.length &&
            rarityTiers.length == metadataUris.length,
            "Array length mismatch"
        );

        uint256[] memory tokenIds = new uint256[](achievementIds.length);

        for (uint256 i = 0; i < achievementIds.length; i++) {
            tokenIds[i] = mintAchievement(
                to,
                achievementIds[i],
                providers[i],
                rarityTiers[i],
                metadataUris[i]
            );
        }

        return tokenIds;
    }

    /**
     * @dev Check if a specific achievement was already minted for a wallet
     */
    function isMinted(address wallet, string memory achievementId) public view returns (bool) {
        bytes32 mintHash = keccak256(abi.encodePacked(wallet, achievementId));
        return alreadyMinted[mintHash];
    }

    /**
     * @dev Get the original earner of an achievement (for provenance)
     */
    function getOriginalEarner(uint256 tokenId) public view returns (address) {
        return achievements[tokenId].originalEarner;
    }

    /**
     * @dev Get full achievement data
     */
    function getAchievementData(uint256 tokenId) public view returns (AchievementData memory) {
        return achievements[tokenId];
    }

    // Required overrides
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
