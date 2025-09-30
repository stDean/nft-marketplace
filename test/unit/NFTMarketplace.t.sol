// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DeployNFTMarketplace, HelperConfig, NFTMarketplace} from "script/NFTMarketplace.s.sol";
import {MockERC721WithRoyalty} from "test/mocks/MockERC721WithRoyalty.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract NFTMarketplaceTest is Test {
    DeployNFTMarketplace deployer;
    HelperConfig helperConfig;
    NFTMarketplace nftMarketplace;
    HelperConfig.NetworkConfig config;
    MockERC20 mockERC20;
    MockERC721WithRoyalty mockNFT;

    address user = makeAddr("user");
    address buyer = makeAddr("buyer");
    address creator = makeAddr("creator");
    address token1 = makeAddr("token1");
    address token2 = makeAddr("token2");
    uint256 tokenId = 1;
    address treasury;
    address nativeToken;
    uint256 protocolFee;

    uint256 constant LISTING_PRICE = 1 ether;
    uint256 immutable expiry = block.timestamp + 7 days;

    function setUp() external {
        deployer = new DeployNFTMarketplace();
        (nftMarketplace, helperConfig) = deployer.run();
        config = helperConfig.getConfig();
        nativeToken = nftMarketplace.NATIVE_TOKEN();
        treasury = config.treasury;
        protocolFee = config.protocolFee;

        mockNFT = new MockERC721WithRoyalty(creator, 500); // 5% royalty
        mockNFT.mint(user, tokenId);
        vm.prank(user);
        mockNFT.approve(address(nftMarketplace), tokenId);

        // Deploy mock ERC20 for testing
        mockERC20 = new MockERC20();
        vm.prank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(address(mockERC20));
    }

    // ========================== CONSTRUCTOR/INITIALIZATION TEST =============================
    function test_ConstructorRevertIFProtocolFeeTooHigh() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__FeeTooHigh.selector);
        new NFTMarketplace(5_000, treasury);
    }

    function test_ConstructorRevertIFTreasuryIsZeroAddress() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidTreasury.selector);
        new NFTMarketplace(protocolFee, address(0));
    }

    function test_ConstructorShouldInitializeCorrectly() public view {
        assertEq(nftMarketplace.s_treasury(), treasury);
        assertEq(nftMarketplace.s_protocolFee(), protocolFee);
        assertEq(nftMarketplace.getSupportedTokens().length, 2);
        assertEq(nftMarketplace.getSupportedTokens()[0], nativeToken);
    }

    // ========================== PAYMENT TOKEN MANAGEMENT TESTS =============================
    function test_AddPaymentToken() public {
        vm.prank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(token1);

        address[] memory tokens = nftMarketplace.getSupportedTokens();
        assertEq(tokens.length, 3);
        assertEq(tokens[0], nativeToken);
        assertEq(tokens[2], token1);
    }

    function test_AddPaymentTokenRevertWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        nftMarketplace.addPaymentToken(token1);
    }

    function test_AddPaymentTokenEmitsEvent() public {
        vm.prank(nftMarketplace.owner());
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.PaymentTokenAdded(token1);
        nftMarketplace.addPaymentToken(token1);
    }

    function test_AddPaymentTokenRevertWhenNativeToken() public {
        vm.prank(nftMarketplace.owner());
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NativeTokenAlreadySupported.selector);
        nftMarketplace.addPaymentToken(nativeToken);
    }

    function test_AddPaymentTokenRevertWhenAlreadySupported() public {
        vm.startPrank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(token1);

        vm.expectRevert(NFTMarketplace.NFTMarketplace__TokenAlreadySupported.selector);
        nftMarketplace.addPaymentToken(token1);
        vm.stopPrank();
    }

    function test_RemovePaymentToken() public {
        vm.startPrank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(token1);
        nftMarketplace.addPaymentToken(token2);

        address[] memory tokensBefore = nftMarketplace.getSupportedTokens();
        assertEq(tokensBefore.length, 4);

        nftMarketplace.removePaymentToken(token1);

        address[] memory tokensAfter = nftMarketplace.getSupportedTokens();
        assertEq(tokensAfter.length, 3);
        assertEq(tokensAfter[0], nativeToken);
        assertEq(tokensAfter[2], token2);
        vm.stopPrank();
    }

    function test_RemovePaymentTokenEmitsEvent() public {
        vm.startPrank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(token1);

        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.PaymentTokenRemoved(token1);
        nftMarketplace.removePaymentToken(token1);
        vm.stopPrank();
    }

    function test_RemovePaymentTokenRevertWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        nftMarketplace.removePaymentToken(token1);
    }

    function test_RemovePaymentTokenRevertWhenNativeToken() public {
        vm.prank(nftMarketplace.owner());
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NativeTokenCannotBeRemoved.selector);
        nftMarketplace.removePaymentToken(nativeToken);
    }

    function test_RemovePaymentTokenRevertWhenNotSupported() public {
        vm.prank(nftMarketplace.owner());
        vm.expectRevert(NFTMarketplace.NFTMarketplace__TokenAlreadySupported.selector);
        nftMarketplace.removePaymentToken(token1);
    }

    // ========================== PROTOCOL FEE MANAGEMENT TESTS =============================
    function test_UpdateProtocolFee() public {
        uint256 newFee = 300; // 3%

        vm.prank(nftMarketplace.owner());
        nftMarketplace.updateProtocolFee(newFee);

        assertEq(nftMarketplace.s_protocolFee(), newFee);
    }

    function test_UpdateProtocolFeeEmitsEvent() public {
        vm.prank(nftMarketplace.owner());
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.ProtocolFeeUpdated(300);
        nftMarketplace.updateProtocolFee(300);
    }

    function test_UpdateProtocolFeeRevertWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        nftMarketplace.updateProtocolFee(300);
    }

    function test_UpdateProtocolFeeRevertWhenFeeTooHigh() public {
        vm.prank(nftMarketplace.owner());
        vm.expectRevert(NFTMarketplace.NFTMarketplace__FeeTooHigh.selector);
        nftMarketplace.updateProtocolFee(1500); // 15% - too high
    }

    // ========================== TREASURY MANAGEMENT TESTS =============================
    function test_UpdateTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(nftMarketplace.owner());
        nftMarketplace.updateTreasury(newTreasury);

        assertEq(nftMarketplace.s_treasury(), newTreasury);
    }

    function test_UpdateTreasuryEmitsEvent() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(nftMarketplace.owner());
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.TreasuryUpdated(newTreasury);
        nftMarketplace.updateTreasury(newTreasury);
    }

    function test_UpdateTreasuryRevertWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        nftMarketplace.updateTreasury(makeAddr("newTreasury"));
    }

    function test_UpdateTreasuryRevertWhenZeroAddress() public {
        vm.prank(nftMarketplace.owner());
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidTreasury.selector);
        nftMarketplace.updateTreasury(address(0));
    }

    // ========================== List Item TESTS =============================

    function test_ItemListRevertsWhenPriceIsZero() public {
        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__PriceMustBeGreaterThanZero.selector);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, 0, 0);
    }

    function test_ItemListRevertsForUnsupportedPaymentToken() public {
        address unsupportedToken = makeAddr("unsupportedToken");
        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__UnsupportedPaymentToken.selector);
        nftMarketplace.listItem(address(mockNFT), tokenId, unsupportedToken, 1 ether, 0);
    }

    function test_ItemListRevertsForInvalidExpiry() public {
        uint256 currentTime = 1000; // Arbitrary future timestamp
        vm.warp(currentTime);
        // Test case 1: expiry is in the past (definitely invalid)
        uint256 pastExpiry = currentTime - 100; // 900 (non-zero and in the past)

        // vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidExpiry.selector);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, 1 ether, pastExpiry);

        // Test case 2: expiry is exactly current time (also invalid)
        uint256 currentExpiry = block.timestamp;

        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidExpiry.selector);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, 1 ether, currentExpiry);
    }

    function test_ListItemRevertsWhenNotNFTOwner() public {
        // User doesn't own the token they're trying to list
        MockERC721WithRoyalty anotherNFT = new MockERC721WithRoyalty(creator, 500);
        anotherNFT.mint(makeAddr("otherUser"), tokenId); // Mint to different user

        vm.prank(user); // But user tries to list it
        vm.expectRevert(); // Should revert on transferFrom
        nftMarketplace.listItem(address(anotherNFT), tokenId, nativeToken, LISTING_PRICE, expiry);
    }

    function test_ListItemRevertsWhenNotApproved() public {
        // User owns but didn't approve marketplace
        MockERC721WithRoyalty anotherNFT = new MockERC721WithRoyalty(creator, 500);
        anotherNFT.mint(user, tokenId);

        vm.prank(user);
        vm.expectRevert(); // Should revert on transferFrom
        nftMarketplace.listItem(address(anotherNFT), tokenId, nativeToken, LISTING_PRICE, expiry);
    }

    function test_ItemListSuccessfully() public {
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, LISTING_PRICE, expiry);

        // Verify the listing was created correctly
        (address seller, address paymentToken, uint256 price, uint256 _expiry, bool active) =
            nftMarketplace.s_listings(address(mockNFT), tokenId);
        assertEq(seller, user);
        assertEq(paymentToken, nativeToken);
        assertEq(price, LISTING_PRICE);
        assertEq(_expiry, expiry);
        assertTrue(active);

        // Verify NFT was transferred to marketplace
        assertEq(mockNFT.ownerOf(tokenId), address(nftMarketplace));
    }

    function test_ListItemEmitsEvent() public {
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.ItemListed(user, address(mockNFT), tokenId, nativeToken, LISTING_PRICE, expiry);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, LISTING_PRICE, expiry);
    }

    function test_ListItemOverwritesExistingListing() public {
        // Create first listing
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, LISTING_PRICE, expiry);

        // Create second listing for same NFT - should overwrite without transferring
        uint256 newPrice = 2 ether;
        uint256 newExpiry = expiry + 1 days;

        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, newPrice, newExpiry);

        // Verify the listing was updated
        (,, uint256 price, uint256 _expiry,) = nftMarketplace.s_listings(address(mockNFT), tokenId);
        assertEq(price, newPrice);
        assertEq(_expiry, newExpiry);

        // NFT should still be with marketplace
        assertEq(mockNFT.ownerOf(tokenId), address(nftMarketplace));
    }

    // ========================== BUY ITEM TESTS =============================
    function test_BuyItemWithNativeToken() public {
        // List NFT for sale
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, LISTING_PRICE, expiry);

        // Buy NFT with native token
        vm.deal(buyer, LISTING_PRICE);
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 sellerBalanceBefore = user.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 creatorBalanceBefore = creator.balance; // Track creator balance for royalty

        vm.prank(buyer);
        nftMarketplace.buyItem{value: LISTING_PRICE}(address(mockNFT), tokenId);

        // Verify NFT transferred to buyer
        assertEq(mockNFT.ownerOf(tokenId), buyer);

        // Verify listing is inactive
        (,,,, bool active) = nftMarketplace.s_listings(address(mockNFT), tokenId);
        assertFalse(active);

        // Verify fund distribution with royalty (protocol fee = 2.5%, royalty = 5%)
        uint256 _protocolFee = (LISTING_PRICE * protocolFee) / 10000; // 2.5%
        uint256 royaltyAmount = (LISTING_PRICE * 500) / 10000; // 5% royalty
        uint256 sellerProceeds = LISTING_PRICE - _protocolFee - royaltyAmount;

        assertEq(user.balance, sellerBalanceBefore + sellerProceeds);
        assertEq(treasury.balance, treasuryBalanceBefore + _protocolFee);
        assertEq(creator.balance, creatorBalanceBefore + royaltyAmount); // Creator receives royalty
        assertEq(buyer.balance, buyerBalanceBefore - LISTING_PRICE);
    }

    function test_BuyItemWithERC20Token() public {
        // Mint ERC20 tokens to buyer and approve marketplace
        mockERC20.mint(buyer, LISTING_PRICE);
        vm.prank(buyer);
        mockERC20.approve(address(nftMarketplace), LISTING_PRICE);

        // List NFT for sale with ERC20
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), tokenId, address(mockERC20), LISTING_PRICE, expiry);

        uint256 sellerBalanceBefore = mockERC20.balanceOf(user);
        uint256 treasuryBalanceBefore = mockERC20.balanceOf(nftMarketplace.s_treasury());
        uint256 creatorBalanceBefore = mockERC20.balanceOf(creator); // Track creator balance

        vm.prank(buyer);
        nftMarketplace.buyItem(address(mockNFT), tokenId);

        // Verify NFT transferred to buyer
        assertEq(mockNFT.ownerOf(tokenId), buyer);

        // Verify fund distribution with royalty
        uint256 _protocolFee = (LISTING_PRICE * protocolFee) / 10000; // 2.5%
        uint256 royaltyAmount = (LISTING_PRICE * 500) / 10000; // 5% royalty
        uint256 sellerProceeds = LISTING_PRICE - _protocolFee - royaltyAmount;

        assertEq(mockERC20.balanceOf(user), sellerBalanceBefore + sellerProceeds);
        assertEq(mockERC20.balanceOf(nftMarketplace.s_treasury()), treasuryBalanceBefore + _protocolFee);
        assertEq(mockERC20.balanceOf(creator), creatorBalanceBefore + royaltyAmount); // Creator receives royalty
        assertEq(mockERC20.balanceOf(buyer), 0);
    }

    function test_RoyaltyInfoIsCorrect() public view {
        uint256 salePrice = 1 ether;
        (address receiver, uint256 royaltyAmount) = mockNFT.royaltyInfo(tokenId, salePrice);

        assertEq(receiver, creator);
        assertEq(royaltyAmount, (salePrice * 500) / 10000); // 5% of 1 ether
    }

    // Test that the marketplace handles NFTs without royalty correctly
    function test_BuyItemWithNonRoyaltyNFT() public {
        // Create a simple NFT without royalty support
        MockERC721WithRoyalty simpleNFT = new MockERC721WithRoyalty(address(0), 0); // No royalty
        simpleNFT.mint(user, 2); // Mint tokenId 2
        vm.prank(user);
        simpleNFT.approve(address(nftMarketplace), 2);

        // List the non-royalty NFT
        vm.prank(user);
        nftMarketplace.listItem(address(simpleNFT), 2, nativeToken, LISTING_PRICE, expiry);

        vm.deal(buyer, LISTING_PRICE);
        uint256 sellerBalanceBefore = user.balance;
        uint256 treasuryBalanceBefore = treasury.balance;

        vm.prank(buyer);
        nftMarketplace.buyItem{value: LISTING_PRICE}(address(simpleNFT), 2);

        // Verify distribution without royalty
        uint256 _protocolFee = (LISTING_PRICE * protocolFee) / 10000;
        uint256 sellerProceeds = LISTING_PRICE - _protocolFee;

        assertEq(user.balance, sellerBalanceBefore + sellerProceeds);
        assertEq(treasury.balance, treasuryBalanceBefore + _protocolFee);
        assertEq(simpleNFT.ownerOf(2), buyer);
    }

    // ========================== CREATE AUCTION TESTS =============================
    function test_CreateAuctionSuccess() public {
        vm.prank(user);
        nftMarketplace.createAuction(
            address(mockNFT),
            tokenId,
            address(mockERC20), // Using ERC20 for payment
            1 ether, // startPrice
            1.5 ether, // reservePrice
            1 days // duration
        );

        // Verify auction was created correctly
        (
            address seller,
            address paymentToken,
            uint256 startPrice,
            uint256 reservePrice,
            uint256 startTime,
            uint256 endTime,
            address highestBidder,
            uint256 highestBid,
            bool settled
        ) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertEq(seller, user);
        assertEq(paymentToken, address(mockERC20));
        assertEq(startPrice, 1 ether);
        assertEq(reservePrice, 1.5 ether);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + 1 days);
        assertEq(highestBidder, address(0));
        assertEq(highestBid, 0);
        assertFalse(settled);

        // Verify NFT was transferred to marketplace
        assertEq(mockNFT.ownerOf(tokenId), address(nftMarketplace));
    }

    function test_CreateAuctionWithNativeToken() public {
        vm.prank(user);
        nftMarketplace.createAuction(
            address(mockNFT),
            tokenId,
            nativeToken, // Using native ETH
            0.5 ether, // startPrice
            1 ether, // reservePrice
            2 days // duration
        );

        (, address paymentToken, uint256 startPrice,,,,,,) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertEq(paymentToken, nativeToken);
        assertEq(startPrice, 0.5 ether);
    }

    function test_CreateAuctionWithZeroReserve() public {
        vm.prank(user);
        nftMarketplace.createAuction(
            address(mockNFT),
            tokenId,
            address(mockERC20),
            1 ether,
            0, // No reserve price
            1 days
        );

        (,,, uint256 reservePrice,,,,,) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertEq(reservePrice, 0);
    }

    function test_CreateAuctionEmitsEvent() public {
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.AuctionCreated(
            user,
            address(mockNFT),
            tokenId,
            address(mockERC20),
            1 ether,
            1.5 ether,
            block.timestamp,
            block.timestamp + 1 days
        );
        nftMarketplace.createAuction(address(mockNFT), tokenId, address(mockERC20), 1 ether, 1.5 ether, 1 days);
    }

    function test_CreateAuctionRevertWhenUnsupportedPaymentToken() public {
        address unsupportedToken = makeAddr("unsupportedToken");

        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__UnsupportedPaymentToken.selector);
        nftMarketplace.createAuction(address(mockNFT), tokenId, unsupportedToken, 1 ether, 1.5 ether, 1 days);
    }

    function test_CreateAuctionRevertWhenDurationTooShort() public {
        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidDuration.selector);
        nftMarketplace.createAuction(
            address(mockNFT),
            tokenId,
            address(mockERC20),
            1 ether,
            1.5 ether,
            14 minutes // Less than MIN_AUCTION_DURATION (15 minutes)
        );
    }

    function test_CreateAuctionRevertWhenDurationTooLong() public {
        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidDuration.selector);
        nftMarketplace.createAuction(
            address(mockNFT),
            tokenId,
            address(mockERC20),
            1 ether,
            1.5 ether,
            31 days // More than MAX_AUCTION_DURATION (30 days)
        );
    }

    function test_CreateAuctionRevertWhenStartPriceZero() public {
        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__StartPriceMustBeGreaterThanZero.selector);
        nftMarketplace.createAuction(
            address(mockNFT),
            tokenId,
            address(mockERC20),
            0, // Zero start price
            1.5 ether,
            1 days
        );
    }

    function test_CreateAuctionRevertWhenNotNFTOwner() public {
        // Create another NFT owned by different user
        MockERC721WithRoyalty anotherNFT = new MockERC721WithRoyalty(creator, 500);
        anotherNFT.mint(makeAddr("otherUser"), 2);

        vm.prank(user); // user doesn't own tokenId 2
        vm.expectRevert(); // Should revert on transferFrom
        nftMarketplace.createAuction(address(anotherNFT), 2, address(mockERC20), 1 ether, 1.5 ether, 1 days);
    }

    function test_CreateAuctionRevertWhenNotApproved() public {
        // Create NFT that user owns but didn't approve marketplace for
        MockERC721WithRoyalty anotherNFT = new MockERC721WithRoyalty(creator, 500);
        anotherNFT.mint(user, 2);
        // Note: No approval given to marketplace

        vm.prank(user);
        vm.expectRevert(); // Should revert on transferFrom
        nftMarketplace.createAuction(address(anotherNFT), 2, address(mockERC20), 1 ether, 1.5 ether, 1 days);
    }

    function test_CreateAuctionAllowsExactMinDuration() public {
        vm.prank(user);
        nftMarketplace.createAuction(
            address(mockNFT),
            tokenId,
            address(mockERC20),
            1 ether,
            1.5 ether,
            15 minutes // Exactly MIN_AUCTION_DURATION
        );

        (,,,,, uint256 endTime,,,) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertEq(endTime, block.timestamp + 15 minutes);
    }

    function test_CreateAuctionAllowsExactMaxDuration() public {
        vm.prank(user);
        nftMarketplace.createAuction(
            address(mockNFT),
            tokenId,
            address(mockERC20),
            1 ether,
            1.5 ether,
            30 days // Exactly MAX_AUCTION_DURATION
        );

        (,,,,, uint256 endTime,,,) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertEq(endTime, block.timestamp + 30 days);
    }

    function test_CreateAuctionMultipleAuctionsDifferentTokens() public {
        // Mint another NFT to user
        mockNFT.mint(user, 2);
        vm.prank(user);
        mockNFT.approve(address(nftMarketplace), 2);

        // Create first auction
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, address(mockERC20), 1 ether, 1.5 ether, 1 days);

        // Create second auction for different token
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), 2, nativeToken, 2 ether, 3 ether, 2 days);

        // Verify both auctions exist and are independent
        (, address paymentToken, uint256 startPrice,,,,,,) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        (, address paymentToken2, uint256 startPrice2,,,,,,) = nftMarketplace.s_auctions(address(mockNFT), 2);

        assertEq(paymentToken, address(mockERC20));
        assertEq(paymentToken2, nativeToken);
        assertEq(startPrice, 1 ether);
        assertEq(startPrice2, 2 ether);
    }

    function test_CreateAuctionOverwritesExistingListing() public {
        // First create a fixed price listing
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, 1 ether, expiry);

        // Verify listing is active and NFT is with marketplace
        (,,,, bool activeBefore) = nftMarketplace.s_listings(address(mockNFT), tokenId);
        assertTrue(activeBefore);
        assertEq(mockNFT.ownerOf(tokenId), address(nftMarketplace));

        // Then create an auction for the same NFT
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, address(mockERC20), 1 ether, 1.5 ether, 1 days);

        // Verify auction was created
        (address seller, address paymentToken,,,,,,,) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertEq(seller, user);
        assertEq(paymentToken, address(mockERC20));

        // Verify the original listing is now inactive
        (,,,, bool activeAfter) = nftMarketplace.s_listings(address(mockNFT), tokenId);
        assertFalse(activeAfter);

        // Verify NFT is still with marketplace
        assertEq(mockNFT.ownerOf(tokenId), address(nftMarketplace));
    }

    function test_CreateAuctionRevertWhenConvertingOthersListing() public {
        // User lists an NFT
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), tokenId, nativeToken, 1 ether, expiry);

        // Another user tries to create an auction for the same NFT
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotListingOwner.selector);
        nftMarketplace.createAuction(address(mockNFT), tokenId, address(mockERC20), 1 ether, 1.5 ether, 1 days);
    }

    function test_CreateAuctionWithLargePriceValues() public {
        uint256 largePrice = type(uint256).max / 2; // Large but safe value

        vm.prank(user);
        nftMarketplace.createAuction(
            address(mockNFT), tokenId, address(mockERC20), largePrice, largePrice + 1 ether, 1 days
        );

        (,, uint256 startPrice, uint256 reservePrice,,,,,) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertEq(startPrice, largePrice);
        assertEq(reservePrice, largePrice + 1 ether);
    }

    // ========================== PLACE BID TESTS =============================
    function test_PlaceBidFirstBidWithNativeToken() public {
        // Create auction with native token
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        // Place first bid
        vm.deal(buyer, 1.1 ether);
        vm.prank(buyer);
        nftMarketplace.placeBid{value: 1.1 ether}(address(mockNFT), tokenId, 1.1 ether);

        (,,,,,, address highestBidder, uint256 highestBid,) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertEq(highestBidder, buyer);
        assertEq(highestBid, 1.1 ether);
    }

    function test_PlaceBidFirstBidWithERC20() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, address(mockERC20), 1 ether, 1.5 ether, 1 days);

        // Mint and approve tokens
        mockERC20.mint(buyer, 1.1 ether);
        vm.prank(buyer);
        mockERC20.approve(address(nftMarketplace), 1.1 ether);

        vm.prank(buyer);
        nftMarketplace.placeBid(address(mockNFT), tokenId, 1.1 ether);

        (,,,,,, address highestBidder, uint256 highestBid,) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertEq(highestBidder, buyer);
        assertEq(highestBid, 1.1 ether);
    }

    function test_PlaceBidOutbidPreviousBidderWithNative() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        // First bid
        address bidder1 = makeAddr("bidder1");
        vm.deal(bidder1, 1.1 ether);
        vm.prank(bidder1);
        nftMarketplace.placeBid{value: 1.1 ether}(address(mockNFT), tokenId, 1.1 ether);

        // Second bid (5% higher)
        uint256 secondBid = 1.1 ether + (1.1 ether * 5 / 100); // 1.155 ether
        vm.deal(buyer, secondBid);
        uint256 bidder1BalanceBefore = bidder1.balance;

        vm.prank(buyer);
        nftMarketplace.placeBid{value: secondBid}(address(mockNFT), tokenId, secondBid);

        (,,,,,, address highestBidder, uint256 highestBid,) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertEq(highestBidder, buyer);
        assertEq(highestBid, secondBid);
        assertEq(bidder1.balance, bidder1BalanceBefore + 1.1 ether); // Refunded
    }

    function test_PlaceBidRevertWhenAuctionNotStarted() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        // Try to bid before auction starts (impossible since it starts immediately)
        // But test with time travel to future auction
        vm.warp(block.timestamp - 1); // Go back in time

        vm.deal(buyer, 1.1 ether);
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__AuctionNotActive.selector);
        nftMarketplace.placeBid{value: 1.1 ether}(address(mockNFT), tokenId, 1.1 ether);
    }

    function test_PlaceBidRevertWhenAuctionEnded() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        // Fast forward past auction end
        vm.warp(block.timestamp + 2 days);

        vm.deal(buyer, 1.1 ether);
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__AuctionNotActive.selector);
        nftMarketplace.placeBid{value: 1.1 ether}(address(mockNFT), tokenId, 1.1 ether);
    }

    function test_PlaceBidRevertWhenBidBelowStartPrice() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        vm.deal(buyer, 0.9 ether);
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__BidTooLow.selector);
        nftMarketplace.placeBid{value: 0.9 ether}(address(mockNFT), tokenId, 0.9 ether);
    }

    function test_PlaceBidRevertWhenBidBelow5PercentIncrement() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        // First bid
        address bidder1 = makeAddr("bidder1");
        vm.deal(bidder1, 1.1 ether);
        vm.prank(bidder1);
        nftMarketplace.placeBid{value: 1.1 ether}(address(mockNFT), tokenId, 1.1 ether);

        // Second bid with insufficient increment (less than 5%)
        vm.deal(buyer, 1.14 ether); // 1.14 < 1.155 (5% of 1.1)
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__BidTooLow.selector);
        nftMarketplace.placeBid{value: 1.14 ether}(address(mockNFT), tokenId, 1.14 ether);
    }

    function test_PlaceBidRevertWhenIncorrectETHAmount() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        vm.deal(buyer, 1.2 ether);
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__IncorrectETHamount.selector);
        nftMarketplace.placeBid{value: 1.2 ether}(address(mockNFT), tokenId, 1.1 ether); // Different amounts
    }

    function test_PlaceBidRevertWhenETHForERC20Auction() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, address(mockERC20), 1 ether, 1.5 ether, 1 days);

        mockERC20.mint(buyer, 1.1 ether);
        vm.prank(buyer);
        mockERC20.approve(address(nftMarketplace), 1.1 ether);

        vm.deal(buyer, 1.1 ether);
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__ETHNotRequired.selector);
        nftMarketplace.placeBid{value: 1.1 ether}(address(mockNFT), tokenId, 1.1 ether);
    }

    function test_PlaceBidEmitsBidPlacedEvent() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        vm.deal(buyer, 1.1 ether);
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.BidPlaced(buyer, address(mockNFT), tokenId, 1.1 ether, nativeToken);
        nftMarketplace.placeBid{value: 1.1 ether}(address(mockNFT), tokenId, 1.1 ether);
    }

    function test_PlaceBidStoresBidInMapping() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        vm.deal(buyer, 1.1 ether);
        vm.prank(buyer);
        nftMarketplace.placeBid{value: 1.1 ether}(address(mockNFT), tokenId, 1.1 ether);

        uint256 storedBid = nftMarketplace.s_bids(address(mockNFT), tokenId, buyer);
        assertEq(storedBid, 1.1 ether);
    }

    // ========================== SETTLE AUCTION TESTS =============================
    function test_SettleAuctionSuccess() public {
        // Create and complete auction
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        // Place winning bid above reserve
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        nftMarketplace.placeBid{value: 2 ether}(address(mockNFT), tokenId, 2 ether);

        // Fast forward to end of auction
        vm.warp(block.timestamp + 2 days);

        vm.prank(user);
        nftMarketplace.settleAuction(address(mockNFT), tokenId);

        // Verify auction settled and NFT transferred
        (,,,,,,,, bool settled) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertTrue(settled);
        assertEq(mockNFT.ownerOf(tokenId), buyer);
    }

    function test_SettleAuctionRevertWhenAuctionNotEnded() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__AuctionNotEnded.selector);
        nftMarketplace.settleAuction(address(mockNFT), tokenId);
    }

    function test_SettleAuctionRevertWhenAlreadySettled() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        nftMarketplace.placeBid{value: 2 ether}(address(mockNFT), tokenId, 2 ether);

        vm.warp(block.timestamp + 2 days);

        // Settle first time
        vm.prank(user);
        nftMarketplace.settleAuction(address(mockNFT), tokenId);

        // Try to settle again
        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__AuctionSettled.selector);
        nftMarketplace.settleAuction(address(mockNFT), tokenId);
    }

    function test_SettleAuctionRevertWhenReserveNotMet() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        // Bid below reserve
        vm.deal(buyer, 1.4 ether);
        vm.prank(buyer);
        nftMarketplace.placeBid{value: 1.4 ether}(address(mockNFT), tokenId, 1.4 ether);

        vm.warp(block.timestamp + 2 days);

        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__ReserveNotMet.selector);
        nftMarketplace.settleAuction(address(mockNFT), tokenId);
    }

    function test_SettleAuctionEmitsEvent() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 1.5 ether, 1 days);

        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        nftMarketplace.placeBid{value: 2 ether}(address(mockNFT), tokenId, 2 ether);

        vm.warp(block.timestamp + 2 days);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.AuctionSettled(buyer, user, address(mockNFT), tokenId, 2 ether, nativeToken);
        nftMarketplace.settleAuction(address(mockNFT), tokenId);
    }

    function test_SettleAuctionWithERC20Payment() public {
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, address(mockERC20), 1 ether, 1.5 ether, 1 days);

        // Bid with ERC20
        mockERC20.mint(buyer, 2 ether);
        vm.prank(buyer);
        mockERC20.approve(address(nftMarketplace), 2 ether);
        vm.prank(buyer);
        nftMarketplace.placeBid(address(mockNFT), tokenId, 2 ether);

        vm.warp(block.timestamp + 2 days);

        vm.prank(user);
        nftMarketplace.settleAuction(address(mockNFT), tokenId);

        // Verify settlement
        (,,,,,,,, bool settled) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertTrue(settled);
        assertEq(mockNFT.ownerOf(tokenId), buyer);
    }

    function test_SettleAuctionWithZeroReserve() public {
        // Auction with no reserve (reservePrice = 0)
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), tokenId, nativeToken, 1 ether, 0, 1 days);

        // Even small bid should work
        vm.deal(buyer, 1.1 ether);
        vm.prank(buyer);
        nftMarketplace.placeBid{value: 1.1 ether}(address(mockNFT), tokenId, 1.1 ether);

        vm.warp(block.timestamp + 2 days);

        vm.prank(user);
        nftMarketplace.settleAuction(address(mockNFT), tokenId); // Should not revert

        (,,,,,,,, bool settled) = nftMarketplace.s_auctions(address(mockNFT), tokenId);
        assertTrue(settled);
    }

    // ========================== BULK LIST ITEMS TESTS =============================
    function test_BulkListItemsSuccess() public {
        // Mint multiple NFTs to user (starting from tokenId 2 since 1 is already minted in setup)
        uint256[] memory tokenIds = new uint256[](3);

        // Fix: Use i=0,1,2 as array indices, and tokenIds 2,3,4 as actual token IDs
        for (uint256 i = 0; i < 3; i++) {
            uint256 _tokenId = i + 2; // This gives us tokenIds 2, 3, 4
            tokenIds[i] = _tokenId; // Correct array indexing: tokenIds[0]=2, tokenIds[1]=3, tokenIds[2]=4
            mockNFT.mint(user, _tokenId);
        }

        vm.prank(user);
        mockNFT.setApprovalForAll(address(nftMarketplace), true);

        // Prepare bulk listing data
        address[] memory nftContracts = new address[](3);
        address[] memory paymentTokens = new address[](3);
        uint256[] memory prices = new uint256[](3);
        uint256[] memory expiries = new uint256[](3);

        for (uint256 i = 0; i < 3; i++) {
            nftContracts[i] = address(mockNFT);
            paymentTokens[i] = nativeToken;
            prices[i] = LISTING_PRICE + i * 0.1 ether;
            expiries[i] = expiry + i * 1 days;
        }

        vm.prank(user);
        nftMarketplace.bulkListItems(nftContracts, tokenIds, paymentTokens, prices, expiries);

        // Verify all listings were created correctly
        for (uint256 i = 0; i < 3; i++) {
            uint256 _tokenId = tokenIds[i]; // Get the actual tokenId from our array

            (address seller, address paymentToken, uint256 price, uint256 _expiry, bool active) =
                nftMarketplace.s_listings(address(mockNFT), _tokenId);

            assertEq(seller, user);
            assertEq(paymentToken, nativeToken);
            assertEq(price, prices[i]);
            assertEq(_expiry, expiries[i]);
            assertTrue(active);
            assertEq(mockNFT.ownerOf(_tokenId), address(nftMarketplace));
        }
    }

    function test_BulkListItemsRevertWhenArrayLengthMismatch() public {
        address[] memory nftContracts = new address[](2);
        uint256[] memory tokenIds = new uint256[](3); // Different length
        address[] memory paymentTokens = new address[](2);
        uint256[] memory prices = new uint256[](2);
        uint256[] memory expiries = new uint256[](2);

        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__ArrayLengthMismatch.selector);
        nftMarketplace.bulkListItems(nftContracts, tokenIds, paymentTokens, prices, expiries);
    }

    function test_BulkListItemsRevertWhenTooManyItems() public {
        uint256 itemCount = 53; // Exceeds 50 limit
        address[] memory nftContracts = new address[](itemCount);
        uint256[] memory tokenIds = new uint256[](itemCount);
        address[] memory paymentTokens = new address[](itemCount);
        uint256[] memory prices = new uint256[](itemCount);
        uint256[] memory expiries = new uint256[](itemCount);

        // Mint and approve all NFTs
        for (uint256 i = 2; i < itemCount; i++) {
            mockNFT.mint(user, i);
        }
        vm.prank(user);
        mockNFT.setApprovalForAll(address(nftMarketplace), true);

        // Fill arrays
        for (uint256 i = 0; i < itemCount; i++) {
            nftContracts[i] = address(mockNFT);
            tokenIds[i] = i;
            paymentTokens[i] = nativeToken;
            prices[i] = LISTING_PRICE;
            expiries[i] = expiry;
        }

        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__TooManyItems.selector);
        nftMarketplace.bulkListItems(nftContracts, tokenIds, paymentTokens, prices, expiries);
    }

    function test_BulkListItemsWithMixedPaymentTokens() public {
        // Setup ERC20 token support
        address erc20Token = makeAddr("erc20Token");
        vm.prank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(erc20Token);

        // Mint 2nd NFTs
        mockNFT.mint(user, 2);
        vm.prank(user);
        mockNFT.setApprovalForAll(address(nftMarketplace), true);

        address[] memory nftContracts = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);
        address[] memory paymentTokens = new address[](2);
        uint256[] memory prices = new uint256[](2);
        uint256[] memory expiries = new uint256[](2);

        // First item with native token
        nftContracts[0] = address(mockNFT);
        tokenIds[0] = 1;
        paymentTokens[0] = nativeToken;
        prices[0] = LISTING_PRICE;
        expiries[0] = expiry;

        // Second item with ERC20 token
        nftContracts[1] = address(mockNFT);
        tokenIds[1] = 2;
        paymentTokens[1] = erc20Token;
        prices[1] = LISTING_PRICE * 2;
        expiries[1] = expiry + 1 days;

        vm.prank(user);
        nftMarketplace.bulkListItems(nftContracts, tokenIds, paymentTokens, prices, expiries);

        // Verify mixed payment tokens are handled correctly
        (, address paymentToken1,,,) = nftMarketplace.s_listings(address(mockNFT), 1);
        (, address paymentToken2,,,) = nftMarketplace.s_listings(address(mockNFT), 2);

        assertEq(paymentToken1, nativeToken);
        assertEq(paymentToken2, erc20Token);
    }

    function test_BulkListItemsGasOptimization() public {
        // Mint 10 NFTs
        uint256 itemCount = 10;
        for (uint256 i = 2; i <= itemCount; i++) {
            mockNFT.mint(user, i);
        }
        vm.prank(user);
        mockNFT.setApprovalForAll(address(nftMarketplace), true);

        // Prepare arrays
        address[] memory nftContracts = new address[](itemCount);
        uint256[] memory tokenIds = new uint256[](itemCount);
        address[] memory paymentTokens = new address[](itemCount);
        uint256[] memory prices = new uint256[](itemCount);
        uint256[] memory expiries = new uint256[](itemCount);

        for (uint256 i = 0; i < itemCount; i++) {
            nftContracts[i] = address(mockNFT);
            tokenIds[i] = i + 1;
            paymentTokens[i] = nativeToken;
            prices[i] = LISTING_PRICE;
            expiries[i] = expiry;
        }

        // Test gas usage for bulk operation
        vm.prank(user);
        uint256 gasStart = gasleft();
        nftMarketplace.bulkListItems(nftContracts, tokenIds, paymentTokens, prices, expiries);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for bulk listing 10 items:", gasUsed);

        // Verify all items were listed
        for (uint256 i = 1; i <= itemCount; i++) {
            (,,,, bool active) = nftMarketplace.s_listings(address(mockNFT), i);
            assertTrue(active);
        }
    }

    function test_BulkListItemsRevertForSingleInvalidItem() public {
        // Mint 3 NFTs
        for (uint256 i = 2; i <= 3; i++) {
            mockNFT.mint(user, i);
        }
        vm.prank(user);
        mockNFT.setApprovalForAll(address(nftMarketplace), true);

        address[] memory nftContracts = new address[](3);
        uint256[] memory tokenIds = new uint256[](3);
        address[] memory paymentTokens = new address[](3);
        uint256[] memory prices = new uint256[](3);
        uint256[] memory expiries = new uint256[](3);

        // Two valid items
        for (uint256 i = 0; i < 2; i++) {
            nftContracts[i] = address(mockNFT);
            tokenIds[i] = i + 1;
            paymentTokens[i] = nativeToken;
            prices[i] = LISTING_PRICE;
            expiries[i] = expiry;
        }

        // One invalid item (unsupported payment token)
        nftContracts[2] = address(mockNFT);
        tokenIds[2] = 3;
        paymentTokens[2] = makeAddr("unsupportedToken"); // This will cause revert
        prices[2] = LISTING_PRICE;
        expiries[2] = expiry;

        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__UnsupportedPaymentToken.selector);
        nftMarketplace.bulkListItems(nftContracts, tokenIds, paymentTokens, prices, expiries);

        // Verify no items were listed (entire transaction reverts)
        for (uint256 i = 1; i <= 3; i++) {
            (,,,, bool active) = nftMarketplace.s_listings(address(mockNFT), i);
            assertFalse(active); // All should be inactive due to revert
        }
    }

    function test_BulkListItemsWithZeroItems() public {
        address[] memory nftContracts = new address[](0);
        uint256[] memory tokenIds = new uint256[](0);
        address[] memory paymentTokens = new address[](0);
        uint256[] memory prices = new uint256[](0);
        uint256[] memory expiries = new uint256[](0);

        vm.prank(user);
        nftMarketplace.bulkListItems(nftContracts, tokenIds, paymentTokens, prices, expiries);

        // Should not revert and execute successfully with zero items
        assertTrue(true); // Just confirm no revert
    }

    // ========================== BULK BUY ITEMS TESTS =============================
    function test_BulkBuyItemsSuccessWithNativeToken() public {
        // List multiple NFTs for sale with native token
        address[] memory nftContracts = new address[](3);
        uint256[] memory tokenIds = new uint256[](3);
        uint256 totalPrice = 0;

        // Mint and list 3 NFTs
        for (uint256 i = 0; i < 3; i++) {
            uint256 _tokenId = i + 2;
            tokenIds[i] = _tokenId;
            nftContracts[i] = address(mockNFT);

            mockNFT.mint(user, _tokenId);
            vm.prank(user);
            mockNFT.approve(address(nftMarketplace), _tokenId);

            vm.prank(user);
            nftMarketplace.listItem(address(mockNFT), _tokenId, nativeToken, LISTING_PRICE + (i * 0.1 ether), expiry);

            totalPrice += LISTING_PRICE + (i * 0.1 ether);
        }

        // Buy all items in bulk
        vm.deal(buyer, totalPrice);
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 sellerBalanceBefore = user.balance;

        vm.prank(buyer);
        nftMarketplace.bulkBuyItems{value: totalPrice}(nftContracts, tokenIds);

        // Verify all NFTs transferred to buyer
        for (uint256 i = 0; i < 3; i++) {
            uint256 _tokenId = tokenIds[i];
            assertEq(mockNFT.ownerOf(_tokenId), buyer);

            // Verify listings are inactive
            (,,,, bool active) = nftMarketplace.s_listings(address(mockNFT), _tokenId);
            assertFalse(active);
        }

        // Verify buyer paid correct amount
        assertEq(buyer.balance, buyerBalanceBefore - totalPrice);
    }

    function test_BulkBuyItemsSuccessWithERC20Token() public {
        // List multiple NFTs for sale with ERC20
        address[] memory nftContracts = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);
        uint256 totalPrice = 0;

        // Mint and list 2 NFTs
        for (uint256 i = 0; i < 2; i++) {
            uint256 _tokenId = i + 2;
            tokenIds[i] = _tokenId;
            nftContracts[i] = address(mockNFT);

            mockNFT.mint(user, _tokenId);
            vm.prank(user);
            mockNFT.approve(address(nftMarketplace), _tokenId);

            uint256 price = LISTING_PRICE + (i * 0.1 ether);
            vm.prank(user);
            nftMarketplace.listItem(address(mockNFT), _tokenId, address(mockERC20), price, expiry);

            totalPrice += price;
        }

        // Mint and approve ERC20 tokens for buyer
        mockERC20.mint(buyer, totalPrice);
        vm.prank(buyer);
        mockERC20.approve(address(nftMarketplace), totalPrice);

        uint256 sellerBalanceBefore = mockERC20.balanceOf(user);
        uint256 treasuryBalanceBefore = mockERC20.balanceOf(treasury);

        vm.prank(buyer);
        nftMarketplace.bulkBuyItems(nftContracts, tokenIds);

        // Verify all NFTs transferred to buyer
        for (uint256 i = 0; i < 2; i++) {
            uint256 _tokenId = tokenIds[i];
            assertEq(mockNFT.ownerOf(_tokenId), buyer);
        }

        // Verify ERC20 tokens transferred correctly
        assertEq(mockERC20.balanceOf(buyer), 0); // Buyer spent all tokens
        assertTrue(mockERC20.balanceOf(user) > sellerBalanceBefore); // Seller received payment
        assertTrue(mockERC20.balanceOf(treasury) > treasuryBalanceBefore); // Protocol fee collected
    }

    function test_BulkBuyItemsWithMixedPaymentTokens() public {
        // List NFTs with mixed payment tokens (native and ERC20)
        address[] memory nftContracts = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);

        // First item: Native token
        mockNFT.mint(user, 2);
        vm.prank(user);
        mockNFT.approve(address(nftMarketplace), 2);
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 2, nativeToken, 1 ether, expiry);

        // Second item: ERC20 token
        mockNFT.mint(user, 3);
        vm.prank(user);
        mockNFT.approve(address(nftMarketplace), 3);
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 3, address(mockERC20), 1.5 ether, expiry);

        nftContracts[0] = address(mockNFT);
        nftContracts[1] = address(mockNFT);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        // Prepare buyer funds
        vm.deal(buyer, 1 ether); // For native token item
        mockERC20.mint(buyer, 1.5 ether); // For ERC20 token item
        vm.prank(buyer);
        mockERC20.approve(address(nftMarketplace), 1.5 ether);

        vm.prank(buyer);
        nftMarketplace.bulkBuyItems{value: 1 ether}(nftContracts, tokenIds);

        // Verify both NFTs purchased
        assertEq(mockNFT.ownerOf(2), buyer);
        assertEq(mockNFT.ownerOf(3), buyer);
    }

    function test_BulkBuyItemsRevertWhenArrayLengthMismatch() public {
        address[] memory nftContracts = new address[](2);
        uint256[] memory tokenIds = new uint256[](3); // Different length

        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__ArrayLengthMismatch.selector);
        nftMarketplace.bulkBuyItems(nftContracts, tokenIds);
    }

    function test_BulkBuyItemsRevertWhenTooManyItems() public {
        uint256 itemCount = 21; // Exceeds 20 limit
        address[] memory nftContracts = new address[](itemCount);
        uint256[] memory tokenIds = new uint256[](itemCount);

        for (uint256 i = 0; i < itemCount; i++) {
            nftContracts[i] = address(mockNFT);
            tokenIds[i] = i + 1;
        }

        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__TooManyItems.selector);
        nftMarketplace.bulkBuyItems(nftContracts, tokenIds);
    }

    function test_BulkBuyItemsRevertWhenItemNotForSale() public {
        // List only one NFT
        mockNFT.mint(user, 2);
        vm.prank(user);
        mockNFT.approve(address(nftMarketplace), 2);
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 2, nativeToken, 1 ether, expiry);

        // Try to buy two items (one not listed)
        address[] memory nftContracts = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);

        nftContracts[0] = address(mockNFT);
        nftContracts[1] = address(mockNFT);
        tokenIds[0] = 2; // Listed
        tokenIds[1] = 3; // Not listed

        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__ItemNotForSale.selector);
        nftMarketplace.bulkBuyItems{value: 2 ether}(nftContracts, tokenIds);
    }

    function test_BulkBuyItemsRevertWhenListingExpired() public {
        // Create a valid listing first (expiry in future)
        mockNFT.mint(user, 2);
        vm.prank(user);
        mockNFT.approve(address(nftMarketplace), 2);
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 2, nativeToken, 1 ether, block.timestamp + 1 days); // Valid expiry

        // Fast forward past the expiry
        vm.warp(block.timestamp + 2 days); // Now the listing is expired

        address[] memory nftContracts = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);

        nftContracts[0] = address(mockNFT);
        tokenIds[0] = 2;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__ListingExpired.selector);
        nftMarketplace.bulkBuyItems{value: 1 ether}(nftContracts, tokenIds);
    }

    function test_BulkBuyItemsRevertWhenInsufficientNativePayment() public {
        // List two NFTs with native token
        for (uint256 i = 2; i <= 3; i++) {
            mockNFT.mint(user, i);
            vm.prank(user);
            mockNFT.approve(address(nftMarketplace), i);
            vm.prank(user);
            nftMarketplace.listItem(address(mockNFT), i, nativeToken, 1 ether, expiry);
        }

        address[] memory nftContracts = new address[](2);
        uint256[] memory tokenIds = new uint256[](2);

        nftContracts[0] = address(mockNFT);
        nftContracts[1] = address(mockNFT);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        // Send insufficient ETH
        vm.deal(buyer, 1.5 ether); // Only 1.5 ETH for 2 ETH total
        vm.prank(buyer);
        vm.expectRevert();
        nftMarketplace.bulkBuyItems{value: 1.5 ether}(nftContracts, tokenIds);
    }

    function test_BulkBuyItemsRefundExcessNativePayment() public {
        // List one NFT
        mockNFT.mint(user, 2);
        vm.prank(user);
        mockNFT.approve(address(nftMarketplace), 2);
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 2, nativeToken, 1 ether, expiry);

        address[] memory nftContracts = new address[](1);
        uint256[] memory tokenIds = new uint256[](1);

        nftContracts[0] = address(mockNFT);
        tokenIds[0] = 2;

        // Send excess ETH
        vm.deal(buyer, 2 ether);
        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        nftMarketplace.bulkBuyItems{value: 2 ether}(nftContracts, tokenIds);

        // Verify NFT purchased and excess refunded
        assertEq(mockNFT.ownerOf(2), buyer);
        assertEq(buyer.balance, buyerBalanceBefore - 1 ether); // Only 1 ETH spent, 1 ETH refunded
    }

    function test_BulkBuyItemsGasOptimization() public {
        // List 10 NFTs
        uint256 itemCount = 10;
        address[] memory nftContracts = new address[](itemCount);
        uint256[] memory tokenIds = new uint256[](itemCount);
        uint256 totalPrice = 0;

        for (uint256 i = 0; i < itemCount; i++) {
            uint256 _tokenId = i + 2;
            tokenIds[i] = _tokenId;
            nftContracts[i] = address(mockNFT);

            mockNFT.mint(user, _tokenId);
            vm.prank(user);
            mockNFT.approve(address(nftMarketplace), _tokenId);

            vm.prank(user);
            nftMarketplace.listItem(address(mockNFT), _tokenId, nativeToken, 1 ether, expiry);

            totalPrice += 1 ether;
        }

        // Test gas usage for bulk purchase
        vm.deal(buyer, totalPrice);
        vm.prank(buyer);
        uint256 gasStart = gasleft();
        nftMarketplace.bulkBuyItems{value: totalPrice}(nftContracts, tokenIds);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for bulk buying 10 items:", gasUsed);

        // Verify all items purchased
        for (uint256 i = 0; i < itemCount; i++) {
            uint256 _tokenId = tokenIds[i];
            assertEq(mockNFT.ownerOf(_tokenId), buyer);
        }
    }

    function test_BulkBuyItemsAtomicFailure() public {
        // List 3 NFTs with valid expiries first
        for (uint256 i = 2; i <= 4; i++) {
            mockNFT.mint(user, i);
            vm.prank(user);
            mockNFT.approve(address(nftMarketplace), i);

            // Create all with valid expiries first
            vm.prank(user);
            nftMarketplace.listItem(address(mockNFT), i, nativeToken, 1 ether, block.timestamp + 1 days);
        }

        // Then expire one of them by fast forwarding
        vm.warp(block.timestamp + 2 days); // Now tokenId 3 is expired (but we need to identify which one)

        address[] memory nftContracts = new address[](3);
        uint256[] memory tokenIds = new uint256[](3);

        for (uint256 i = 0; i < 3; i++) {
            nftContracts[i] = address(mockNFT);
            tokenIds[i] = i + 2;
        }

        vm.deal(buyer, 3 ether);
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__ListingExpired.selector);
        nftMarketplace.bulkBuyItems{value: 3 ether}(nftContracts, tokenIds);

        // Verify no NFTs were purchased (atomic transaction)
        for (uint256 i = 2; i <= 4; i++) {
            assertEq(mockNFT.ownerOf(i), address(nftMarketplace)); // Still with marketplace, not bought
        }
    }

    function test_BulkBuyItemsWithZeroItems() public {
        address[] memory nftContracts = new address[](0);
        uint256[] memory tokenIds = new uint256[](0);

        vm.prank(buyer);
        nftMarketplace.bulkBuyItems(nftContracts, tokenIds);

        // Should not revert and execute successfully with zero items
        assertTrue(true); // Just confirm no revert
    }
}
