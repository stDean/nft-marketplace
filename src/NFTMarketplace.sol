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
    event ItemListed(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId,
        address paymentToken,
        uint256 price,
        uint256 expiry
    );
    event ItemSold(
        address indexed buyer,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 protocolFee
    );
    event AuctionCreated(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId,
        address paymentToken,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 startTime,
        uint256 endTime
    );
    event BidPlaced(
        address indexed bidder,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 amount,
        address paymentToken
    );

    // ================= ERRORS ======================
    error NFTMarketplace__FeeTooHigh();
    error NFTMarketplace__InvalidTreasury();
    error NFTMarketplace__NativeTokenAlreadySupported();
    error NFTMarketplace__TokenAlreadySupported();
    error NFTMarketplace__NativeTokenCannotBeRemoved();
    error NFTMarketplace__PriceMustBeGreaterThanZero();
    error NFTMarketplace__UnsupportedPaymentToken();
    error NFTMarketplace__InvalidExpiry();
    error NFTMarketplace__NotListingOwner();
    error NFTMarketplace__ItemNotForSale();
    error NFTMarketplace__ListingExpired();
    error NFTMarketplace__RoyaltyExceedPrice();
    error NFTMarketplace__TransferFailed();
    error NFTMarketplace__InsufficientPayment();
    error NFTMarketplace__InvalidDuration();
    error NFTMarketplace__StartPriceMustBeGreaterThanZero();
    error NFTMarketplace__AuctionNotActive();
    error NFTMarketplace__AuctionSettled();
    error NFTMarketplace__BidTooLow();
    error NFTMarketplace__IncorrectETHamount();
    error NFTMarketplace__ETHNotRequired();

    // ================= FUNCTIONS ======================
    // Required to receive native tokens
    receive() external payable {}

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

    /**
     * @notice Add a new payment token to the supported tokens list
     * @param _token The address of the ERC20 token to add
     * @dev Only callable by the owner. Cannot add native token or already supported tokens
     */
    function addPaymentToken(address _token) external onlyOwner {
        if (_token == NATIVE_TOKEN) revert NFTMarketplace__NativeTokenAlreadySupported();
        if (!s_supportedTokens.add(_token)) revert NFTMarketplace__TokenAlreadySupported();

        emit PaymentTokenAdded(_token);
    }

    /**
     * @notice Remove a payment token from the supported tokens list
     * @param _token The address of the ERC20 token to remove
     * @dev Only callable by the owner. Cannot remove native token
     */
    function removePaymentToken(address _token) external onlyOwner {
        if (_token == NATIVE_TOKEN) revert NFTMarketplace__NativeTokenCannotBeRemoved();
        if (!s_supportedTokens.remove(_token)) revert NFTMarketplace__TokenAlreadySupported();

        emit PaymentTokenRemoved(_token);
    }

    /**
     * @notice Update the protocol fee percentage
     * @param _newFee The new fee percentage in basis points (100 = 1%)
     * @dev Only callable by the owner. Fee cannot exceed 10% (1000 basis points)
     */
    function updateProtocolFee(uint256 _newFee) external onlyOwner {
        if (_newFee > 1000) revert NFTMarketplace__FeeTooHigh();

        s_protocolFee = _newFee;
        emit ProtocolFeeUpdated(_newFee);
    }

    /**
     * @notice Update the treasury address where protocol fees are sent
     * @param _newTreasury The new treasury address
     * @dev Only callable by the owner. Treasury cannot be zero address
     */
    function updateTreasury(address _newTreasury) external onlyOwner {
        if (_newTreasury == address(0)) revert NFTMarketplace__InvalidTreasury();

        s_treasury = _newTreasury;
        emit TreasuryUpdated(_newTreasury);
    }

    /**
     * @notice List an NFT for sale at a fixed price or update an existing listing
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the NFT token to list
     * @param paymentToken The token address for payment (address(0) for native ETH)
     * @param price The sale price in the specified payment token
     * @param expiry Timestamp when listing expires (0 for no expiry)
     * @dev For new listings: Transfers NFT to marketplace for escrow. Requires prior approval.
     * @dev For existing listings: Updates price and expiry without transferring NFT again.
     * @dev Only the original seller can update an existing listing.
     * @dev Only active listings can be purchased. Expired listings become inactive.
     * @dev Reverts if price is zero, payment token is unsupported, or expiry is invalid.
     */
    function listItem(address nftContract, uint256 tokenId, address paymentToken, uint256 price, uint256 expiry)
        external
        nonReentrant
    {
        if (price == 0) revert NFTMarketplace__PriceMustBeGreaterThanZero();
        if (!s_supportedTokens.contains(paymentToken)) revert NFTMarketplace__UnsupportedPaymentToken();
        if (expiry != 0 && expiry <= block.timestamp) revert NFTMarketplace__InvalidExpiry();

        // Check if marketplace already owns the NFT (updating existing listing)
        address currentOwner = IERC721(nftContract).ownerOf(tokenId);

        if (currentOwner != address(this)) {
            // Marketplace doesn't own it yet - transfer from seller (new listing)
            IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        } else {
            // Marketplace already owns it - verify seller is updating their own listing
            Listing memory existingListing = s_listings[nftContract][tokenId];
            if (existingListing.seller != msg.sender) {
                revert NFTMarketplace__NotListingOwner();
            }
            // If it's the same seller, no transfer needed (listing update)
        }

        s_listings[nftContract][tokenId] =
            Listing({seller: msg.sender, paymentToken: paymentToken, price: price, expiry: expiry, active: true});
        emit ItemListed(msg.sender, nftContract, tokenId, paymentToken, price, expiry);
    }

    /**
     * @notice Purchase an NFT listed for sale
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the NFT token to purchase
     * @dev For native token payments: Payment must be sent with the transaction (msg.value must equal or exceed listing price)
     * @dev For ERC20 token payments: Buyer must have approved the marketplace to spend the required amount
     * @dev Reverts if:
     *      - Item is not for sale (NFTMarketplace__ItemNotForSale)
     *      - Listing has expired (NFTMarketplace__ListingExpired)
     *      - Insufficient native token payment (NFTMarketplace__InsufficientPayment)
     *      - ERC20 transfer fails (transferFrom reverts)
     * @dev Automatically handles EIP-2981 royalties and protocol fees
     * @dev Transfers NFT ownership to buyer and distributes funds to seller, royalty recipient, and protocol treasury
     */
    function buyItem(address nftContract, uint256 tokenId) external payable nonReentrant {
        Listing memory listing = s_listings[nftContract][tokenId];

        // Validate listing is active and not expired
        if (!listing.active) revert NFTMarketplace__ItemNotForSale();
        if (listing.expiry != 0 && block.timestamp >= listing.expiry) revert NFTMarketplace__ListingExpired();

        // Handle payment based on token type
        if (listing.paymentToken == NATIVE_TOKEN) {
            // Native token payment
            if (msg.value < listing.price) revert NFTMarketplace__InsufficientPayment();
        } else {
            // ERC20 token payment - transfer tokens from buyer to marketplace
            IERC20(listing.paymentToken).transferFrom(msg.sender, address(this), listing.price);
        }

        _executeSale(nftContract, tokenId, listing, msg.sender, listing.price);
    }

    /**
     * @notice Create a new auction for an NFT
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the NFT token to auction
     * @param paymentToken The ERC20 token address to be used for bids
     * @param startPrice The minimum starting bid price (must be > 0)
     * @param reservePrice The hidden minimum price to win the auction (0 = no reserve)
     * @param duration The auction duration in seconds (within min/max bounds)
     * @dev Transfers the NFT from seller to marketplace contract
     * @dev Reverts if:
     *      - Payment token is not supported (NFTMarketplace__UnsupportedPaymentToken)
     *      - Duration is invalid (NFTMarketplace__InvalidDuration)
     *      - Start price is zero (NFTMarketplace__StartPriceMustBeGreaterThanZero)
     *      - NFT transfer fails (ERC721 transferFrom reverts)
     * @dev Auction starts immediately and ends at block.timestamp + duration
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration
    ) external nonReentrant {
        if (!s_supportedTokens.contains(paymentToken)) revert NFTMarketplace__UnsupportedPaymentToken();
        if (duration < MIN_AUCTION_DURATION || duration > MAX_AUCTION_DURATION) {
            revert NFTMarketplace__InvalidDuration();
        }
        if (startPrice == 0) revert NFTMarketplace__StartPriceMustBeGreaterThanZero();

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        // Check if marketplace already owns the NFT (converting from listing to auction)
        address currentOwner = IERC721(nftContract).ownerOf(tokenId);
        if (currentOwner != address(this)) {
            // Marketplace doesn't own it yet - transfer from seller
            IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        } else {
            // Marketplace already owns it - verify seller is updating their own listing
            Listing memory existingListing = s_listings[nftContract][tokenId];
            if (existingListing.seller != msg.sender) {
                revert NFTMarketplace__NotListingOwner();
            }
            // Deactivate the existing listing when converting to auction
            s_listings[nftContract][tokenId].active = false;
        }

        s_auctions[nftContract][tokenId] = Auction({
            seller: msg.sender,
            paymentToken: paymentToken,
            startPrice: startPrice,
            reservePrice: reservePrice,
            startTime: startTime,
            endTime: endTime,
            highestBidder: address(0),
            highestBid: 0,
            settled: false
        });
        emit AuctionCreated(
            msg.sender, nftContract, tokenId, paymentToken, startPrice, reservePrice, startTime, endTime
        );
    }

    /**
     * @notice Place a bid on an active auction
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the NFT token being auctioned
     * @param bidAmount The amount of the bid (in payment token units)
     * @dev For native token auctions: bidAmount must equal msg.value
     * @dev For ERC20 token auctions: bidAmount will be transferred from bidder, msg.value must be 0
     * @dev Reverts if:
     *      - Auction is not active (NFTMarketplace__AuctionNotActive)
     *      - Auction is already settled (NFTMarketplace__AuctionSettled)
     *      - Bid amount is below minimum required (5% above current bid or start price) (NFTMarketplace__BidTooLow)
     *      - Incorrect ETH amount sent for native token auctions (NFTMarketplace__IncorrectETHamount)
     *      - ETH sent for ERC20 token auctions (NFTMarketplace__ETHNotRequired)
     * @dev Automatically refunds previous highest bidder when outbid
     * @dev Stores bid for gas optimization in bulk operations
     */
    function placeBid(address nftContract, uint256 tokenId, uint256 bidAmount) external payable nonReentrant {
        Auction storage auction = s_auctions[nftContract][tokenId];

        if (block.timestamp < auction.startTime || block.timestamp > auction.endTime) {
            revert NFTMarketplace__AuctionNotActive();
        }
        if (auction.settled) revert NFTMarketplace__AuctionSettled();

        address paymentToken = auction.paymentToken;
        uint256 currentBid = auction.highestBid;
        uint256 minBid = currentBid == 0 ? auction.startPrice : currentBid + (currentBid * 5 / 100); // 5% min increment

        if (bidAmount < minBid) revert NFTMarketplace__BidTooLow();

        // Handle payment based on token type
        if (paymentToken == NATIVE_TOKEN) {
            if (msg.value != bidAmount) revert NFTMarketplace__IncorrectETHamount();
            // Refund previous bidder if any
            if (auction.highestBidder != address(0)) {
                _transferNative(auction.highestBidder, currentBid);
            }
        } else {
            if (msg.value != 0) revert NFTMarketplace__ETHNotRequired();
            IERC20(paymentToken).transferFrom(msg.sender, address(this), bidAmount);
            // Refund previous bidder
            if (auction.highestBidder != address(0)) {
                IERC20(paymentToken).transfer(auction.highestBidder, currentBid);
            }
        }

        // Update auction state
        auction.highestBidder = msg.sender;
        auction.highestBid = bidAmount;

        // Store bid for gas optimization in bulk operations
        s_bids[nftContract][tokenId][msg.sender] = bidAmount;

        emit BidPlaced(msg.sender, nftContract, tokenId, bidAmount, paymentToken);
    }

    /**
     * @notice Execute the sale transaction for an NFT
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the NFT token being sold
     * @param listing The listing details containing seller, price, and payment info
     * @param buyer The address of the purchaser
     * @param price The agreed sale price
     * @dev Marks listing as inactive, distributes funds, and transfers NFT ownership
     * @dev Emits ItemSold event upon successful completion
     */
    function _executeSale(address nftContract, uint256 tokenId, Listing memory listing, address buyer, uint256 price)
        internal
    {
        // Mark listing as inactive to prevent double purchases
        s_listings[nftContract][tokenId].active = false;

        // Distribute funds according to protocol fees and royalties
        _distributeFunds(nftContract, tokenId, listing.seller, buyer, listing.paymentToken, price);

        // Transfer NFT ownership from marketplace to buyer
        IERC721(nftContract).transferFrom(address(this), buyer, tokenId);

        emit ItemSold(buyer, listing.seller, nftContract, tokenId, listing.paymentToken, price, s_protocolFee);
    }

    /**
     * @notice Distribute sale proceeds among seller, royalty recipient, and protocol treasury
     * @param nftContract The address of the NFT contract for royalty lookup
     * @param tokenId The ID of the NFT token for royalty calculation
     * @param seller The address of the NFT seller
     * @param // buyer The address of the NFT buyer (unused but maintained for interface)
     * @param paymentToken The token used for payment (address(0) for native ETH)
     * @param price The total sale price before fees and royalties
     * @dev Calculates protocol fee first, then EIP-2981 royalties, remainder goes to seller
     * @dev Handles both native ETH and ERC20 token transfers
     * @dev Reverts if royalty amount exceeds available funds after protocol fee
     */
    function _distributeFunds(
        address nftContract,
        uint256 tokenId,
        address seller,
        address, /* buyer */
        address paymentToken,
        uint256 price
    ) internal {
        // Calculate protocol fee (marketplace commission)
        uint256 protocolFeeAmount = (price * s_protocolFee) / BASIS_POINTS;
        uint256 remainingAmount = price - protocolFeeAmount;

        // Handle EIP-2981 royalty payments if supported by NFT contract
        (address royaltyRecipient, uint256 royaltyAmount) = _getRoyaltyInfo(nftContract, tokenId, price);
        if (royaltyAmount > 0 && royaltyRecipient != address(0)) {
            // Ensure royalty doesn't exceed available funds
            if (royaltyAmount > remainingAmount) revert NFTMarketplace__RoyaltyExceedPrice();

            remainingAmount -= royaltyAmount;

            // Transfer royalty to creator
            if (paymentToken == NATIVE_TOKEN) {
                _transferNative(royaltyRecipient, royaltyAmount);
            } else {
                IERC20(paymentToken).transfer(royaltyRecipient, royaltyAmount);
            }
        }

        // Transfer protocol fee
        if (protocolFeeAmount > 0) {
            if (paymentToken == NATIVE_TOKEN) {
                _transferNative(s_treasury, protocolFeeAmount);
            } else {
                IERC20(paymentToken).transfer(s_treasury, protocolFeeAmount);
            }
        }

        // Transfer remaining to seller
        if (remainingAmount > 0) {
            if (paymentToken == NATIVE_TOKEN) {
                _transferNative(seller, remainingAmount);
            } else {
                IERC20(paymentToken).transfer(seller, remainingAmount);
            }
        }
    }

    /**
     * @notice Retrieve royalty information using EIP-2981 standard
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the NFT token
     * @param salePrice The sale price to calculate royalties from
     * @return recipient The address to receive royalties (address(0) if not supported)
     * @return amount The royalty amount calculated (0 if not supported)
     * @dev Uses try-catch to safely handle NFTs that don't implement EIP-2981
     */
    function _getRoyaltyInfo(address nftContract, uint256 tokenId, uint256 salePrice)
        internal
        view
        returns (address, uint256)
    {
        try IERC2981(nftContract).royaltyInfo(tokenId, salePrice) returns (address recipient, uint256 amount) {
            return (recipient, amount);
        } catch {
            return (address(0), 0);
        }
    }

    /**
     * @notice Safely transfer native ETH to a recipient
     * @param to The address to receive the native tokens
     * @param amount The amount of native tokens to transfer
     * @dev Uses low-level call with gas stipend for reliable transfers
     * @dev Reverts if the transfer fails
     */
    function _transferNative(address to, uint256 amount) internal {
        (bool success,) = to.call{value: amount}("");
        if (!success) revert NFTMarketplace__TransferFailed();
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
