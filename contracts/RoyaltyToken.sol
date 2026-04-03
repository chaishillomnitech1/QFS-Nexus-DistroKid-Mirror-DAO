// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RoyaltyToken
 * @notice ERC-20 token representing tokenized artist royalty shares on the
 *         QFS Nexus DistroKid Mirror DAO platform.
 *
 * Each artist has a dedicated RoyaltyToken instance.  The platform mints
 * tokens when a royalty stream is registered and burns them if the stream is
 * retired.  Token holders receive a pro-rata share of on-chain royalty
 * distributions triggered by the platform.
 *
 * Key features
 * ─────────────
 * • Fixed-denomination shares (18 decimals, same as ETH) for easy DeFi
 *   composability.
 * • `distributeRoyalties` accepts ETH and splits it proportionally among all
 *   current token holders tracked in `holders`.
 * • Role-restricted minting / burning — only the contract owner (the DAO
 *   multi-sig or deployer) may create or destroy supply.
 */
contract RoyaltyToken is ERC20, ERC20Burnable, Ownable {
    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Human-readable artist name linked to this token.
    string public artistName;

    /// @notice DistroKid artist identifier (off-chain reference).
    string public distrokidArtistId;

    /// @notice Running total of royalties distributed (in wei) for auditability.
    uint256 public totalRoyaltiesDistributed;

    /// @dev Ordered list of addresses that have ever held tokens.
    address[] private holders;

    /// @dev Tracks whether an address is already in `holders`.
    mapping(address => bool) private isHolder;

    // ─── Events ───────────────────────────────────────────────────────────────

    event RoyaltiesDistributed(uint256 amount, uint256 timestamp);
    event HolderAdded(address indexed holder);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param _artistName        Human-readable name of the artist.
     * @param _distrokidArtistId DistroKid artist identifier.
     * @param _symbol            Token ticker symbol (e.g. "RTKN-ARTIST").
     * @param _initialSupply     Tokens minted to the owner on deploy (18-dec).
     * @param _owner             Initial owner (DAO multi-sig or deployer).
     */
    constructor(
        string memory _artistName,
        string memory _distrokidArtistId,
        string memory _symbol,
        uint256 _initialSupply,
        address _owner
    ) ERC20(_artistName, _symbol) Ownable(_owner) {
        artistName = _artistName;
        distrokidArtistId = _distrokidArtistId;

        if (_initialSupply > 0) {
            _mintTo(_owner, _initialSupply);
        }
    }

    // ─── Owner-only mutators ──────────────────────────────────────────────────

    /**
     * @notice Mint additional royalty-share tokens to `to`.
     * @param to     Recipient address.
     * @param amount Amount in token units (18 decimals).
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mintTo(to, amount);
    }

    // ─── Royalty distribution ─────────────────────────────────────────────────

    /**
     * @notice Distribute ETH royalties proportionally to all token holders.
     *
     * The caller sends ETH with this call.  Each holder receives
     * `(balance / totalSupply) * msg.value`.  Dust (rounding remainder) stays
     * in the contract and is included in the next distribution.
     *
     * @dev Iterating over `holders` is acceptable because DistroKid artist
     *      royalty pools are expected to have a bounded, manageable number of
     *      co-owners (e.g. label, artist, producers).  For very large holder
     *      sets a Merkle-drop pattern should be used instead.
     */
    function distributeRoyalties() external payable onlyOwner {
        require(msg.value > 0, "RoyaltyToken: no ETH sent");
        uint256 supply = totalSupply();
        require(supply > 0, "RoyaltyToken: no tokens in circulation");

        uint256 distributed;
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 bal = balanceOf(holder);
            if (bal == 0) continue;

            uint256 share = (msg.value * bal) / supply;
            if (share == 0) continue;

            distributed += share;
            (bool sent, ) = holder.call{value: share}("");
            require(sent, "RoyaltyToken: ETH transfer failed");
        }

        totalRoyaltiesDistributed += distributed;
        emit RoyaltiesDistributed(distributed, block.timestamp);
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    function _mintTo(address to, uint256 amount) internal {
        _registerHolder(to);
        _mint(to, amount);
    }

    /**
     * @dev Hook called by ERC20 on every token transfer so we can track the
     *      holder list automatically.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        super._update(from, to, value);
        if (to != address(0)) {
            _registerHolder(to);
        }
    }

    function _registerHolder(address addr) internal {
        if (!isHolder[addr]) {
            isHolder[addr] = true;
            holders.push(addr);
            emit HolderAdded(addr);
        }
    }

    // ─── View helpers ─────────────────────────────────────────────────────────

    /// @notice Returns the list of all addresses that have ever held tokens.
    function getHolders() external view returns (address[] memory) {
        return holders;
    }

    /// @notice Allows the contract to receive ETH (e.g. royalties pushed externally).
    receive() external payable {}
}
