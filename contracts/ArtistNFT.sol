// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ArtistNFT
 * @notice ERC-721 "Guardian NFT" representing an artist's Digital Mirror Twin
 *         on the QFS Nexus DistroKid Mirror DAO platform.
 *
 * Each token is a unique, soulbound-by-default Digital Twin for an artist.
 * Holding an ArtistNFT confers:
 *   1. Proof of identity linked to a DistroKid artist profile.
 *   2. DAO governance voting rights (read by `GovernanceDAO`).
 *   3. Eligibility for RoyaltyToken airdrops and revenue splits.
 *
 * Soulbound behaviour
 * ───────────────────
 * Transfers are disabled by default (`soulbound = true`).  The owner (DAO
 * multi-sig) can toggle transferability if a specific artist requests it
 * (e.g. to move to a different wallet).
 */
contract ArtistNFT is ERC721, ERC721URIStorage, Ownable {
    // ─── State ────────────────────────────────────────────────────────────────

    uint256 private _nextTokenId;

    /// @notice When true, tokens cannot be transferred between wallets.
    bool public soulbound;

    /// @dev Maps tokenId → DistroKid artist identifier (off-chain reference).
    mapping(uint256 => string) public distrokidArtistId;

    /// @dev Maps tokenId → human-readable artist name at time of minting.
    mapping(uint256 => string) public artistName;

    /// @dev Maps tokenId → timestamp when the Digital Twin was created.
    mapping(uint256 => uint256) public mintedAt;

    // ─── Events ───────────────────────────────────────────────────────────────

    event DigitalTwinCreated(
        uint256 indexed tokenId,
        address indexed artist,
        string distrokidArtistId,
        string artistName,
        string tokenURI
    );

    event SoulboundToggled(bool soulbound);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param _owner    Initial owner — typically a DAO multi-sig.
     * @param _soulbound Whether tokens are non-transferable at deploy time.
     */
    constructor(
        address _owner,
        bool _soulbound
    ) ERC721("QFS Nexus Artist Guardian NFT", "GUARDIAN") Ownable(_owner) {
        soulbound = _soulbound;
    }

    // ─── Minting ──────────────────────────────────────────────────────────────

    /**
     * @notice Create a Digital Mirror Twin for an artist.
     * @param to                Wallet address of the artist.
     * @param _distrokidId      DistroKid artist identifier.
     * @param _artistName       Human-readable artist name.
     * @param _tokenURI         IPFS / Arweave URI of the metadata JSON.
     * @return tokenId          The newly minted token ID.
     */
    function createDigitalTwin(
        address to,
        string calldata _distrokidId,
        string calldata _artistName,
        string calldata _tokenURI
    ) external onlyOwner returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);

        distrokidArtistId[tokenId] = _distrokidId;
        artistName[tokenId] = _artistName;
        mintedAt[tokenId] = block.timestamp;

        emit DigitalTwinCreated(tokenId, to, _distrokidId, _artistName, _tokenURI);
    }

    // ─── Soulbound control ────────────────────────────────────────────────────

    /**
     * @notice Toggle soulbound mode on or off (owner only).
     * @param _soulbound New soulbound state.
     */
    function setSoulbound(bool _soulbound) external onlyOwner {
        soulbound = _soulbound;
        emit SoulboundToggled(_soulbound);
    }

    // ─── ERC-721 overrides ────────────────────────────────────────────────────

    /**
     * @dev Blocks transfers when `soulbound` is true.
     *      Minting (from == address(0)) is always allowed.
     *      Burning (to == address(0)) is always allowed so the owner can
     *      retire a Digital Twin.
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (soulbound && from != address(0) && to != address(0)) {
            revert("ArtistNFT: token is soulbound and cannot be transferred");
        }
        return super._update(to, tokenId, auth);
    }

    // ─── Required overrides (ERC721URIStorage) ────────────────────────────────

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ─── View helpers ─────────────────────────────────────────────────────────

    /// @notice Total number of Digital Twins minted (including any burned ones).
    function totalMinted() external view returns (uint256) {
        return _nextTokenId;
    }
}
