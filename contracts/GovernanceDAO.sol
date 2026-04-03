// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ArtistNFT.sol";

/**
 * @title GovernanceDAO
 * @notice On-chain DAO governance for the QFS Nexus DistroKid Mirror DAO.
 *
 * Artists who hold a Guardian NFT (ArtistNFT) can:
 *   1. Submit governance proposals (platform policy, revenue allocation, etc.).
 *   2. Cast FOR / AGAINST / ABSTAIN votes — one vote per Guardian NFT.
 *   3. Execute proposals that reach quorum and a majority FOR vote after the
 *      voting window closes.
 *
 * Design choices
 * ──────────────
 * • Voting power is binary: 1 NFT = 1 vote (Guardian NFT model).
 * • Proposals have a configurable voting period (default 3 days).
 * • Quorum is a minimum number of FOR + AGAINST votes (not counting abstains).
 * • Proposal execution is limited to whitelisted target contracts to prevent
 *   arbitrary calls; the owner can add / remove targets.
 * • The contract does NOT hold funds; it emits `ProposalExecuted` and callers
 *   act on the signal (upgradeable pattern recommended for production).
 */
contract GovernanceDAO {
    // ─── Types ────────────────────────────────────────────────────────────────

    enum VoteChoice {
        FOR,
        AGAINST,
        ABSTAIN
    }

    enum ProposalState {
        Active,
        Defeated,
        Succeeded,
        Executed
    }

    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        uint256 votingEnd;        // Unix timestamp
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool executed;
        /// @dev Optional: encoded call to execute on a whitelisted target.
        address target;
        bytes callData;
    }

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Guardian NFT contract used to verify voting eligibility.
    ArtistNFT public immutable artistNFT;

    /// @notice Owner / DAO admin (typically a multi-sig).
    address public owner;

    /// @notice Duration of the voting window in seconds (default 3 days).
    uint256 public votingPeriod = 3 days;

    /// @notice Minimum combined FOR + AGAINST votes for a proposal to be valid.
    uint256 public quorum = 3;

    uint256 private _proposalCount;

    /// @dev proposalId → Proposal
    mapping(uint256 => Proposal) public proposals;

    /// @dev proposalId → voter address → has voted
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    /// @dev Whitelisted target contracts that proposals may call.
    mapping(address => bool) public whitelistedTargets;

    // ─── Events ───────────────────────────────────────────────────────────────

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        uint256 votingEnd
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        VoteChoice choice,
        uint256 weight
    );

    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalDefeated(uint256 indexed proposalId);

    event QuorumUpdated(uint256 oldQuorum, uint256 newQuorum);
    event VotingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event TargetWhitelisted(address target, bool allowed);

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "GovernanceDAO: caller is not the owner");
        _;
    }

    modifier onlyGuardian() {
        require(
            artistNFT.balanceOf(msg.sender) > 0,
            "GovernanceDAO: must hold a Guardian NFT to participate"
        );
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param _artistNFT  Address of the deployed ArtistNFT contract.
     * @param _owner      DAO admin address.
     * @param _quorum     Minimum quorum (FOR + AGAINST) required.
     * @param _votingPeriod Voting window in seconds.
     */
    constructor(
        address _artistNFT,
        address _owner,
        uint256 _quorum,
        uint256 _votingPeriod
    ) {
        require(_artistNFT != address(0), "GovernanceDAO: zero address");
        require(_owner != address(0), "GovernanceDAO: zero address");
        artistNFT = ArtistNFT(_artistNFT);
        owner = _owner;
        if (_quorum > 0) quorum = _quorum;
        if (_votingPeriod > 0) votingPeriod = _votingPeriod;
    }

    // ─── Proposal lifecycle ───────────────────────────────────────────────────

    /**
     * @notice Submit a new governance proposal.
     * @param _title       Short title of the proposal.
     * @param _description Full description / rationale.
     * @param _target      Optional whitelisted contract to call on execution
     *                     (use address(0) for signal-only proposals).
     * @param _callData    ABI-encoded call for `_target` (empty if no call).
     * @return proposalId  Unique identifier for the new proposal.
     */
    function propose(
        string calldata _title,
        string calldata _description,
        address _target,
        bytes calldata _callData
    ) external onlyGuardian returns (uint256 proposalId) {
        require(bytes(_title).length > 0, "GovernanceDAO: empty title");

        if (_target != address(0)) {
            require(
                whitelistedTargets[_target],
                "GovernanceDAO: target not whitelisted"
            );
        }

        proposalId = _proposalCount++;
        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            title: _title,
            description: _description,
            votingEnd: block.timestamp + votingPeriod,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            executed: false,
            target: _target,
            callData: _callData
        });

        emit ProposalCreated(
            proposalId,
            msg.sender,
            _title,
            proposals[proposalId].votingEnd
        );
    }

    /**
     * @notice Cast a vote on an active proposal.
     * @param proposalId The proposal to vote on.
     * @param choice     FOR (0), AGAINST (1), or ABSTAIN (2).
     */
    function castVote(
        uint256 proposalId,
        VoteChoice choice
    ) external onlyGuardian {
        Proposal storage p = proposals[proposalId];
        require(p.votingEnd != 0, "GovernanceDAO: proposal does not exist");
        require(block.timestamp < p.votingEnd, "GovernanceDAO: voting period ended");
        require(!hasVoted[proposalId][msg.sender], "GovernanceDAO: already voted");

        hasVoted[proposalId][msg.sender] = true;

        // Voting weight = number of Guardian NFTs held (1-NFT-1-vote model).
        uint256 weight = artistNFT.balanceOf(msg.sender);

        if (choice == VoteChoice.FOR) {
            p.forVotes += weight;
        } else if (choice == VoteChoice.AGAINST) {
            p.againstVotes += weight;
        } else {
            p.abstainVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, choice, weight);
    }

    /**
     * @notice Execute a proposal that has succeeded (quorum + majority FOR).
     * @param proposalId The proposal to execute.
     */
    function execute(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(p.votingEnd != 0, "GovernanceDAO: proposal does not exist");
        require(block.timestamp >= p.votingEnd, "GovernanceDAO: voting still active");
        require(!p.executed, "GovernanceDAO: already executed");
        require(
            state(proposalId) == ProposalState.Succeeded,
            "GovernanceDAO: proposal did not succeed"
        );

        p.executed = true;

        if (p.target != address(0) && p.callData.length > 0) {
            (bool success, ) = p.target.call(p.callData);
            require(success, "GovernanceDAO: execution call failed");
        }

        emit ProposalExecuted(proposalId);
    }

    // ─── View helpers ─────────────────────────────────────────────────────────

    /**
     * @notice Returns the current state of a proposal.
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage p = proposals[proposalId];
        require(p.votingEnd != 0, "GovernanceDAO: proposal does not exist");

        if (p.executed) return ProposalState.Executed;
        if (block.timestamp < p.votingEnd) return ProposalState.Active;

        uint256 participation = p.forVotes + p.againstVotes;
        if (participation < quorum || p.forVotes <= p.againstVotes) {
            return ProposalState.Defeated;
        }
        return ProposalState.Succeeded;
    }

    /// @notice Returns the total number of proposals created.
    function proposalCount() external view returns (uint256) {
        return _proposalCount;
    }

    // ─── Owner configuration ──────────────────────────────────────────────────

    /**
     * @notice Update the minimum quorum required for proposals to succeed.
     */
    function setQuorum(uint256 _quorum) external onlyOwner {
        require(_quorum > 0, "GovernanceDAO: quorum must be > 0");
        emit QuorumUpdated(quorum, _quorum);
        quorum = _quorum;
    }

    /**
     * @notice Update the voting window duration.
     */
    function setVotingPeriod(uint256 _period) external onlyOwner {
        require(_period >= 1 hours, "GovernanceDAO: period too short");
        emit VotingPeriodUpdated(votingPeriod, _period);
        votingPeriod = _period;
    }

    /**
     * @notice Add or remove a whitelisted execution target.
     */
    function setWhitelistedTarget(
        address target,
        bool allowed
    ) external onlyOwner {
        require(target != address(0), "GovernanceDAO: zero address");
        whitelistedTargets[target] = allowed;
        emit TargetWhitelisted(target, allowed);
    }

    /**
     * @notice Transfer DAO admin rights to a new address (e.g. multi-sig).
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "GovernanceDAO: zero address");
        owner = newOwner;
    }
}
