// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ForgedItems
 * @dev NFT contract for Dreadland forged items with full provenance tracking
 *
 * Key features:
 * - Items forged from verified achievements (via backend relayer)
 * - Full provenance: forger, trade count, ownership history
 * - Batch trade recording for gas efficiency
 * - Relayer-only functions for gasless transactions
 * - Creator royalties via ERC-2981 compatible getters
 */
contract ForgedItems is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard {
    uint256 private _nextTokenId;

    // Relayer address for gasless transactions
    address public relayer;

    // Royalty configuration (in basis points, e.g., 500 = 5%)
    uint96 public royaltyBps = 500; // 5% default
    address public royaltyReceiver;

    // Item provenance - complete ownership history
    struct Provenance {
        address forger;           // Original player who forged the item
        address currentOwner;     // Current owner (updated on trades)
        uint256 forgedAt;         // Timestamp when forged
        uint256 lastTradeAt;      // Timestamp of last trade (0 if never traded)
        uint32 tradeCount;        // Total number of trades
        string itemId;            // Internal item ID (e.g., "thunderfury_blessed_blade")
        string achievementId;     // Source achievement ID
        string rarity;            // "Legendary", "Epic", etc.
    }

    // Trade record for batch processing
    struct TradeRecord {
        uint256 tokenId;
        address from;
        address to;
        uint256 priceGold;        // In-game gold amount
        uint256 tradedAt;         // Timestamp
        bytes32 txRef;            // Backend transaction reference
    }

    // Token ID => Provenance
    mapping(uint256 => Provenance) public provenance;

    // Token ID => Trade history (array of trade records)
    mapping(uint256 => TradeRecord[]) public tradeHistory;

    // Prevent duplicate forges: hash(forger + achievementId) => tokenId
    mapping(bytes32 => uint256) public forgeRecords;

    // Backend transaction reference => processed flag (prevent replay)
    mapping(bytes32 => bool) public processedTxRefs;

    // Events
    event ItemForged(
        uint256 indexed tokenId,
        address indexed forger,
        string itemId,
        string achievementId,
        string rarity
    );

    event TradeRecorded(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        uint256 priceGold,
        uint32 newTradeCount,
        bytes32 txRef
    );

    event TradeBatchRecorded(
        uint256 batchSize,
        bytes32 batchId
    );

    event RelayerUpdated(address oldRelayer, address newRelayer);

    modifier onlyRelayer() {
        require(msg.sender == relayer || msg.sender == owner(), "Not authorized");
        _;
    }

    constructor(address _relayer) ERC721("Dreadland Forged Item", "FORGE") Ownable(msg.sender) {
        relayer = _relayer;
        royaltyReceiver = msg.sender;
    }

    /**
     * @dev Forge a new item from a verified achievement. Only callable by relayer.
     * @param to Wallet address to mint to (the player who forged it)
     * @param itemId Internal item ID from items.json
     * @param achievementId Source achievement ID
     * @param rarity Rarity tier string
     * @param metadataUri URI pointing to item metadata JSON
     */
    function forgeItem(
        address to,
        string memory itemId,
        string memory achievementId,
        string memory rarity,
        string memory metadataUri
    ) public onlyRelayer returns (uint256) {
        // Prevent duplicate forges
        bytes32 forgeHash = keccak256(abi.encodePacked(to, achievementId));
        require(forgeRecords[forgeHash] == 0, "Item already forged from this achievement");

        uint256 tokenId = ++_nextTokenId; // Start from 1
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, metadataUri);

        provenance[tokenId] = Provenance({
            forger: to,
            currentOwner: to,
            forgedAt: block.timestamp,
            lastTradeAt: 0,
            tradeCount: 0,
            itemId: itemId,
            achievementId: achievementId,
            rarity: rarity
        });

        forgeRecords[forgeHash] = tokenId;

        emit ItemForged(tokenId, to, itemId, achievementId, rarity);

        return tokenId;
    }

    /**
     * @dev Record a batch of trades. Only callable by relayer.
     * This is the main function called by the chain batching service.
     * @param trades Array of trade records to process
     * @param batchId Unique identifier for this batch
     */
    function recordTradeBatch(
        TradeRecord[] calldata trades,
        bytes32 batchId
    ) external onlyRelayer nonReentrant returns (uint256 processedCount) {
        require(!processedTxRefs[batchId], "Batch already processed");
        processedTxRefs[batchId] = true;

        for (uint256 i = 0; i < trades.length; i++) {
            TradeRecord calldata trade = trades[i];

            // Skip if already processed (individual trade replay protection)
            if (processedTxRefs[trade.txRef]) {
                continue;
            }
            processedTxRefs[trade.txRef] = true;

            // Verify token exists
            if (provenance[trade.tokenId].forgedAt == 0) {
                continue; // Token doesn't exist, skip
            }

            // Update provenance
            Provenance storage p = provenance[trade.tokenId];
            p.currentOwner = trade.to;
            p.lastTradeAt = trade.tradedAt;
            p.tradeCount++;

            // Store trade in history
            tradeHistory[trade.tokenId].push(trade);

            emit TradeRecorded(
                trade.tokenId,
                trade.from,
                trade.to,
                trade.priceGold,
                p.tradeCount,
                trade.txRef
            );

            processedCount++;
        }

        emit TradeBatchRecorded(processedCount, batchId);
    }

    /**
     * @dev Record a single trade (for immediate processing if needed)
     */
    function recordTrade(
        uint256 tokenId,
        address from,
        address to,
        uint256 priceGold,
        bytes32 txRef
    ) external onlyRelayer {
        require(!processedTxRefs[txRef], "Trade already processed");
        require(provenance[tokenId].forgedAt > 0, "Token does not exist");

        processedTxRefs[txRef] = true;

        Provenance storage p = provenance[tokenId];
        p.currentOwner = to;
        p.lastTradeAt = block.timestamp;
        p.tradeCount++;

        TradeRecord memory trade = TradeRecord({
            tokenId: tokenId,
            from: from,
            to: to,
            priceGold: priceGold,
            tradedAt: block.timestamp,
            txRef: txRef
        });
        tradeHistory[tokenId].push(trade);

        emit TradeRecorded(tokenId, from, to, priceGold, p.tradeCount, txRef);
    }

    /**
     * @dev Get full provenance for a token
     */
    function getProvenance(uint256 tokenId) external view returns (Provenance memory) {
        require(provenance[tokenId].forgedAt > 0, "Token does not exist");
        return provenance[tokenId];
    }

    /**
     * @dev Get trade history for a token
     */
    function getTradeHistory(uint256 tokenId) external view returns (TradeRecord[] memory) {
        return tradeHistory[tokenId];
    }

    /**
     * @dev Get trade count for a token
     */
    function getTradeCount(uint256 tokenId) external view returns (uint32) {
        return provenance[tokenId].tradeCount;
    }

    /**
     * @dev Check if an achievement has been forged by an address
     */
    function isForged(address forger, string memory achievementId) external view returns (bool) {
        bytes32 forgeHash = keccak256(abi.encodePacked(forger, achievementId));
        return forgeRecords[forgeHash] != 0;
    }

    /**
     * @dev Get tokenId for a forged achievement
     */
    function getForgedTokenId(address forger, string memory achievementId) external view returns (uint256) {
        bytes32 forgeHash = keccak256(abi.encodePacked(forger, achievementId));
        return forgeRecords[forgeHash];
    }

    // ============ Royalty Functions (ERC-2981 compatible) ============

    /**
     * @dev Returns royalty info for a given token and sale price
     */
    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * royaltyBps) / 10000;
        return (royaltyReceiver, royaltyAmount);
    }

    /**
     * @dev Update royalty configuration. Only callable by owner.
     */
    function setRoyalty(address receiver, uint96 bps) external onlyOwner {
        require(bps <= 1000, "Royalty too high"); // Max 10%
        royaltyReceiver = receiver;
        royaltyBps = bps;
    }

    // ============ Admin Functions ============

    /**
     * @dev Update the relayer address. Only callable by owner.
     */
    function setRelayer(address newRelayer) external onlyOwner {
        require(newRelayer != address(0), "Invalid relayer address");
        address oldRelayer = relayer;
        relayer = newRelayer;
        emit RelayerUpdated(oldRelayer, newRelayer);
    }

    /**
     * @dev Emergency: Mark a batch as unprocessed (for re-processing). Only owner.
     */
    function resetBatch(bytes32 batchId) external onlyOwner {
        processedTxRefs[batchId] = false;
    }

    // ============ Required Overrides ============

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        // ERC-2981 interface ID
        return interfaceId == 0x2a55205a || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Override transfer to update provenance.currentOwner on standard transfers
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = super._update(to, tokenId, auth);

        // Update currentOwner in provenance (for OpenSea/direct transfers)
        if (from != address(0) && to != address(0) && provenance[tokenId].forgedAt > 0) {
            provenance[tokenId].currentOwner = to;
            // Note: Trade count not incremented for direct transfers
            // Chain batching service handles recording with gold price
        }

        return from;
    }
}
