// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;

import {Test, console} from "forge-std/Test.sol";
import {DeployNFTMarketplace, HelperConfig, NFTMarketplace} from "script/NFTMarketplace.s.sol";
import {MockERC721WithRoyalty} from "test/mocks/MockERC721WithRoyalty.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract NFTMarketplaceIntegratedTest is Test {
    DeployNFTMarketplace deployer;
    HelperConfig helperConfig;
    NFTMarketplace nftMarketplace;
    HelperConfig.NetworkConfig config;
    MockERC20 mockERC20;
    MockERC721WithRoyalty mockNFT;

    address user = makeAddr("user");
    address buyer = makeAddr("buyer");
    address creator = makeAddr("creator");
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
        mockNFT.mint(user, 1);
        mockNFT.mint(user, 2);
        mockNFT.mint(user, 3);
        vm.prank(user);
        mockNFT.setApprovalForAll(address(nftMarketplace), true);

        // Deploy mock ERC20 for testing
        mockERC20 = new MockERC20();
        vm.prank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(address(mockERC20));
    }

    // ========================== INTEGRATED FLOW TESTS =============================
    function test_CompleteFlowNativeTokenPurchase() public {
        // User lists NFT for sale with native token
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 1, nativeToken, LISTING_PRICE, expiry);

        // Verify listing
        (address seller, address paymentToken, uint256 price,, bool active) =
            nftMarketplace.s_listings(address(mockNFT), 1);
        assertEq(seller, user);
        assertEq(paymentToken, nativeToken);
        assertEq(price, LISTING_PRICE);
        assertTrue(active);
        assertEq(mockNFT.ownerOf(1), address(nftMarketplace));

        // Buyer purchases with native token
        vm.deal(buyer, LISTING_PRICE);
        uint256 buyerBalanceBefore = buyer.balance;
        uint256 sellerBalanceBefore = user.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 creatorBalanceBefore = creator.balance;

        vm.prank(buyer);
        nftMarketplace.buyItem{value: LISTING_PRICE}(address(mockNFT), 1);

        // Verify purchase completed
        assertEq(mockNFT.ownerOf(1), buyer);
        (,,,, bool activeAfter) = nftMarketplace.s_listings(address(mockNFT), 1);
        assertFalse(activeAfter);

        // Verify fund distribution (protocol fee 2.5%, royalty 5%)
        uint256 protocolFeeAmount = (LISTING_PRICE * protocolFee) / 10000;
        uint256 royaltyAmount = (LISTING_PRICE * 500) / 10000;
        uint256 sellerProceeds = LISTING_PRICE - protocolFeeAmount - royaltyAmount;

        assertEq(user.balance, sellerBalanceBefore + sellerProceeds);
        assertEq(treasury.balance, treasuryBalanceBefore + protocolFeeAmount);
        assertEq(creator.balance, creatorBalanceBefore + royaltyAmount);
        assertEq(buyer.balance, buyerBalanceBefore - LISTING_PRICE);
    }

    function test_CompleteFlowERC20TokenPurchase() public {
        // User lists NFT for sale with ERC20
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 1, address(mockERC20), LISTING_PRICE, expiry);

        // Buyer prepares and purchases with ERC20
        mockERC20.mint(buyer, LISTING_PRICE);
        vm.prank(buyer);
        mockERC20.approve(address(nftMarketplace), LISTING_PRICE);

        uint256 sellerBalanceBefore = mockERC20.balanceOf(user);
        uint256 treasuryBalanceBefore = mockERC20.balanceOf(treasury);
        uint256 creatorBalanceBefore = mockERC20.balanceOf(creator);

        vm.prank(buyer);
        nftMarketplace.buyItem(address(mockNFT), 1);

        // Verify purchase completed
        assertEq(mockNFT.ownerOf(1), buyer);

        // Verify fund distribution
        uint256 protocolFeeAmount = (LISTING_PRICE * protocolFee) / 10000;
        uint256 royaltyAmount = (LISTING_PRICE * 500) / 10000;
        uint256 sellerProceeds = LISTING_PRICE - protocolFeeAmount - royaltyAmount;

        assertEq(mockERC20.balanceOf(user), sellerBalanceBefore + sellerProceeds);
        assertEq(mockERC20.balanceOf(treasury), treasuryBalanceBefore + protocolFeeAmount);
        assertEq(mockERC20.balanceOf(creator), creatorBalanceBefore + royaltyAmount);
        assertEq(mockERC20.balanceOf(buyer), 0);
    }

    function test_CompleteFlowAuctionWithNativeToken() public {
        // User creates auction
        vm.prank(user);
        nftMarketplace.createAuction(
            address(mockNFT),
            1,
            nativeToken,
            1 ether, // startPrice
            1.5 ether, // reservePrice
            1 days // duration
        );

        // Multiple bidders place bids
        address bidder1 = makeAddr("bidder1");
        address bidder2 = makeAddr("bidder2");

        // Bidder 1 places first bid
        vm.deal(bidder1, 1.1 ether);
        vm.prank(bidder1);
        nftMarketplace.placeBid{value: 1.1 ether}(address(mockNFT), 1, 1.1 ether);

        // Bidder 2 outbids with 5% increment
        uint256 bid2Amount = 1.5 ether; // 1.155 ether
        vm.deal(bidder2, bid2Amount);
        vm.prank(bidder2);
        nftMarketplace.placeBid{value: bid2Amount}(address(mockNFT), 1, bid2Amount);

        // Verify auction state
        (,,,,,, address highestBidder, uint256 highestBid,) = nftMarketplace.s_auctions(address(mockNFT), 1);
        assertEq(highestBidder, bidder2);
        assertEq(highestBid, bid2Amount);

        // Bidder 1 should be refunded
        assertEq(bidder1.balance, 1.1 ether); // All ETH used for bid was refunded

        // Settle auction after it ends
        vm.warp(block.timestamp + 2 days);

        uint256 sellerBalanceBefore = user.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 creatorBalanceBefore = creator.balance;

        vm.prank(user);
        nftMarketplace.settleAuction(address(mockNFT), 1);

        // Verify settlement
        (,,,,,,,, bool settled) = nftMarketplace.s_auctions(address(mockNFT), 1);
        assertTrue(settled);
        assertEq(mockNFT.ownerOf(1), bidder2);

        // Verify fund distribution
        uint256 protocolFeeAmount = (bid2Amount * protocolFee) / 10000;
        uint256 royaltyAmount = (bid2Amount * 500) / 10000;
        uint256 sellerProceeds = bid2Amount - protocolFeeAmount - royaltyAmount;

        assertEq(user.balance, sellerBalanceBefore + sellerProceeds);
        assertEq(treasury.balance, treasuryBalanceBefore + protocolFeeAmount);
        assertEq(creator.balance, creatorBalanceBefore + royaltyAmount);
    }
}
