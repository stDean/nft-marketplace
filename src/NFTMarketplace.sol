// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @title NFTMarketplace
 * @notice A decentralized NFT marketplace supporting multiple payment tokens, auctions, bulk operations, and EIP-2981 royalties
 * @dev This contract handles fixed price listings, English auctions, and supports gas optimization techniques
 */
contract NFTMarketplace is ReentrancyGuard, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Struct for fixed price listings
    struct Listing {
        address seller; // Address of the NFT owner who listed the item for sale
        address paymentToken; // Token address used for payment (address(0) = native ETH)
        uint256 price; // Fixed price at which the NFT is being sold
        uint256 expiry; // Timestamp when the listing expires (0 = no expiry)
        bool active; // Whether the listing is currently active and valid
    }

    /// @notice Struct for auction listings
    struct Auction {
        address seller; // Address of the NFT owner who started the auction
        address paymentToken; // Token address used for bids (address(0) = native ETH)
        uint256 startPrice; // Minimum starting bid price for the auction
        uint256 reservePrice; // Secret minimum price that must be met for successful sale
        uint256 startTime; // Timestamp when the auction begins accepting bids
        uint256 endTime; // Timestamp when the auction ends and no more bids accepted
        address highestBidder; // Address of the current highest bidder
        uint256 highestBid; // Current highest bid amount
        bool settled; // Whether the auction has been finalized and NFT transferred
    }

    /// @notice Protocol fee in basis points (e.g., 100 = 1%, 250 = 2.5%)
    uint256 public s_protocolFee;

    /// @notice Protocol fee recipient address (where marketplace fees are sent)
    address public s_treasury;

    /// @notice Supported ERC20 tokens for payments (besides native ETH)
    EnumerableSet.AddressSet private s_supportedTokens;

    /// @notice Basis points for percentage calculations (10000 = 100%)
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Native token address representation (ETH = address(0))
    address public constant NATIVE_TOKEN = address(0);

    /// @notice Minimum auction duration to prevent extremely short auctions
    uint256 public constant MIN_AUCTION_DURATION = 15 minutes;

    /// @notice Maximum auction duration to prevent extremely long lockups
    uint256 public constant MAX_AUCTION_DURATION = 30 days;

    /// @notice Mapping from NFT contract address => token ID => Listing details
    mapping(address => mapping(uint256 => Listing)) public s_listings;

    /// @notice Mapping from NFT contract => token ID => Auction
    mapping(address => mapping(uint256 => Auction)) public s_auctions;

    /// @notice Mapping to track bids for gas optimization: NFT contract => token ID => bidder => bid amount
    mapping(address => mapping(uint256 => mapping(address => uint256))) public s_bids;

    // ================= EVENTS ======================
    event PaymentTokenAdded(address indexed token);
    event PaymentTokenRemoved(address indexed token);
    event ProtocolFeeUpdated(uint256 newFee);
    event TreasuryUpdated(address newTreasury);

    // ================= ERRORS ======================
    /// @notice Thrown when protocol fee exceeds maximum allowed (10%)
    error NFTMarketplace__FeeTooHigh();

    /// @notice Thrown when treasury address is zero address
    error NFTMarketplace__InvalidTreasury();

    /// @notice Thrown when add a native token again
    error NFTMarketplace__NativeTokenAlreadySupported();

    /// @notice Thrown when token already supported
    error NFTMarketplace__TokenAlreadySupported();

    error NFTMarketplace__NativeTokenCannotBeRemoved();

    // ================= FUNCTIONS ======================
    /**
     * @notice Initializes the NFT marketplace contract
     * @param _protocolFee The fee percentage in basis points (100 = 1%)
     * @param _treasury The address that receives protocol fees
     * @dev Sets up initial configuration and adds native ETH as supported payment token
     */
    constructor(uint256 _protocolFee, address _treasury) Ownable(msg.sender) {
        if (_protocolFee > 1000) revert NFTMarketplace__FeeTooHigh(); // Max 10% fee
        if (_treasury == address(0)) revert NFTMarketplace__InvalidTreasury();

        s_protocolFee = _protocolFee;
        s_treasury = _treasury;

        // Add native token as supported by default (ETH payments)
        s_supportedTokens.add(NATIVE_TOKEN);
    }

    function addPaymentToken(address _token) external onlyOwner {
        if (_token == NATIVE_TOKEN) revert NFTMarketplace__NativeTokenAlreadySupported();
        if (!s_supportedTokens.add(_token)) revert NFTMarketplace__TokenAlreadySupported();

        s_supportedTokens.add(_token);
        emit PaymentTokenAdded(_token);
    }

    function removePaymentToken(address _token) external onlyOwner {
        if (_token == NATIVE_TOKEN) revert NFTMarketplace__NativeTokenCannotBeRemoved();
        if (!s_supportedTokens.remove(_token)) revert NFTMarketplace__TokenAlreadySupported();

        s_supportedTokens.remove(_token);
        emit PaymentTokenRemoved(_token);
    }

    function updateProtocolFee(uint256 _newFee) external onlyOwner {
        if (_newFee > 1000) revert NFTMarketplace__FeeTooHigh();

        s_protocolFee = _newFee;
        emit ProtocolFeeUpdated(_newFee);
    }

    function updateTreasury(address _newTreasury) external onlyOwner {
        if (_newTreasury == address(0)) revert NFTMarketplace__InvalidTreasury();

        s_treasury = _newTreasury;
        emit TreasuryUpdated(_newTreasury);
    }

    // ================= GETTERS ======================
    /**
     * @notice Get supported payment tokens
     * @return Array of supported token addresses
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return s_supportedTokens.values();
    }
}
