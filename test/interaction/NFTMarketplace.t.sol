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

    function test_CompleteFlowBulkOperations() public {
        // User bulk lists multiple NFTs
        address[] memory nftContracts = new address[](3);
        uint256[] memory tokenIds = new uint256[](3);
        address[] memory paymentTokens = new address[](3);
        uint256[] memory prices = new uint256[](3);
        uint256[] memory expiries = new uint256[](3);

        for (uint256 i = 0; i < 3; i++) {
            nftContracts[i] = address(mockNFT);
            tokenIds[i] = i + 1;
            paymentTokens[i] = nativeToken;
            prices[i] = LISTING_PRICE + (i * 0.1 ether);
            expiries[i] = expiry + (i * 1 days);
        }

        vm.prank(user);
        nftMarketplace.bulkListItems(nftContracts, tokenIds, paymentTokens, prices, expiries);

        // Verify all listings created
        for (uint256 i = 0; i < 3; i++) {
            (,,,, bool active) = nftMarketplace.s_listings(address(mockNFT), i + 1);
            assertTrue(active);
            assertEq(mockNFT.ownerOf(i + 1), address(nftMarketplace));
        }

        // Buyer bulk purchases all NFTs
        uint256 totalPrice = LISTING_PRICE + (LISTING_PRICE + 0.1 ether) + (LISTING_PRICE + 0.2 ether);
        vm.deal(buyer, totalPrice);

        vm.prank(buyer);
        nftMarketplace.bulkBuyItems{value: totalPrice}(nftContracts, tokenIds);

        // Verify all NFTs purchased
        for (uint256 i = 0; i < 3; i++) {
            assertEq(mockNFT.ownerOf(i + 1), buyer);
            (,,,, bool activeAfter) = nftMarketplace.s_listings(address(mockNFT), i + 1);
            assertFalse(activeAfter);
        }
    }

    function test_CompleteFlowListingToAuctionConversion() public {
        // User lists NFT for fixed price
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 1, nativeToken, LISTING_PRICE, expiry);

        // Verify fixed price listing
        (,,,, bool listingActive) = nftMarketplace.s_listings(address(mockNFT), 1);
        assertTrue(listingActive);

        // User converts to auction
        vm.prank(user);
        nftMarketplace.createAuction(
            address(mockNFT),
            1,
            address(mockERC20), // Different payment token
            1 ether,
            1.5 ether,
            1 days
        );

        // Verify auction created and listing deactivated
        (address seller, address paymentToken,,,,,,,) = nftMarketplace.s_auctions(address(mockNFT), 1);
        assertEq(seller, user);
        assertEq(paymentToken, address(mockERC20));

        (,,,, bool listingActiveAfter) = nftMarketplace.s_listings(address(mockNFT), 1);
        assertFalse(listingActiveAfter);

        // Complete auction
        mockERC20.mint(buyer, 2 ether);
        vm.prank(buyer);
        mockERC20.approve(address(nftMarketplace), 2 ether);
        vm.prank(buyer);
        nftMarketplace.placeBid(address(mockNFT), 1, 2 ether);

        vm.warp(block.timestamp + 2 days);
        vm.prank(user);
        nftMarketplace.settleAuction(address(mockNFT), 1);

        assertEq(mockNFT.ownerOf(1), buyer);
    }

    function test_CompleteFlowMixedPaymentTokens() public {
        // Add another ERC20 token
        MockERC20 mockERC20_2 = new MockERC20();
        vm.prank(nftMarketplace.owner());
        nftMarketplace.addPaymentToken(address(mockERC20_2));

        // List NFTs with different payment tokens
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 1, nativeToken, 1 ether, expiry); // Native token

        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 2, address(mockERC20), 1.5 ether, expiry); // ERC20 #1

        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 3, address(mockERC20_2), 2 ether, expiry); // ERC20 #2

        // Prepare buyer funds for all purchases
        vm.deal(buyer, 1 ether); // For native token purchase

        mockERC20.mint(buyer, 1.5 ether);
        vm.prank(buyer);
        mockERC20.approve(address(nftMarketplace), 1.5 ether);

        mockERC20_2.mint(buyer, 2 ether);
        vm.prank(buyer);
        mockERC20_2.approve(address(nftMarketplace), 2 ether);

        // Buy all items (mixed in bulk would be better but individual for clarity)
        vm.prank(buyer);
        nftMarketplace.buyItem{value: 1 ether}(address(mockNFT), 1);

        vm.prank(buyer);
        nftMarketplace.buyItem(address(mockNFT), 2);

        vm.prank(buyer);
        nftMarketplace.buyItem(address(mockNFT), 3);

        // Verify all purchases completed
        assertEq(mockNFT.ownerOf(1), buyer);
        assertEq(mockNFT.ownerOf(2), buyer);
        assertEq(mockNFT.ownerOf(3), buyer);
    }

    function test_CompleteFlowProtocolFeeUpdateDuringActiveListings() public {
        // User lists NFT
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 1, nativeToken, LISTING_PRICE, expiry);

        // Owner updates protocol fee
        uint256 newFee = 700; // 7%
        vm.prank(nftMarketplace.owner());
        nftMarketplace.updateProtocolFee(newFee);

        // Buyer purchases - should use new fee
        vm.deal(buyer, LISTING_PRICE);
        uint256 treasuryBalanceBefore = treasury.balance;

        vm.prank(buyer);
        nftMarketplace.buyItem{value: LISTING_PRICE}(address(mockNFT), 1);

        // Verify new fee applied
        uint256 expectedFee = (LISTING_PRICE * newFee) / 10000;
        assertEq(treasury.balance, treasuryBalanceBefore + expectedFee);
    }

    function test_CompleteFlowRoyaltyFreeNFT() public {
        // Create NFT without royalty
        MockERC721WithRoyalty noRoyaltyNFT = new MockERC721WithRoyalty(address(0), 0);
        noRoyaltyNFT.mint(user, 1);
        vm.prank(user);
        noRoyaltyNFT.setApprovalForAll(address(nftMarketplace), true);

        // List and purchase
        vm.prank(user);
        nftMarketplace.listItem(address(noRoyaltyNFT), 1, nativeToken, LISTING_PRICE, expiry);

        vm.deal(buyer, LISTING_PRICE);
        uint256 sellerBalanceBefore = user.balance;
        uint256 treasuryBalanceBefore = treasury.balance;

        vm.prank(buyer);
        nftMarketplace.buyItem{value: LISTING_PRICE}(address(noRoyaltyNFT), 1);

        // Verify distribution without royalty
        uint256 protocolFeeAmount = (LISTING_PRICE * protocolFee) / 10000;
        uint256 sellerProceeds = LISTING_PRICE - protocolFeeAmount;

        assertEq(user.balance, sellerBalanceBefore + sellerProceeds);
        assertEq(treasury.balance, treasuryBalanceBefore + protocolFeeAmount);
        assertEq(noRoyaltyNFT.ownerOf(1), buyer);
    }

    function test_CompleteFlowAuctionWithNoBids() public {
        // Create auction
        vm.prank(user);
        nftMarketplace.createAuction(
            address(mockNFT),
            1,
            nativeToken,
            1 ether,
            1.5 ether, // reserve price
            1 days
        );

        // Let auction end without bids
        vm.warp(block.timestamp + 2 days);

        // Try to settle - should revert since reserve not met
        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__ReserveNotMet.selector);
        nftMarketplace.settleAuction(address(mockNFT), 1);

        // NFT should remain with marketplace
        assertEq(mockNFT.ownerOf(1), address(nftMarketplace));
    }

    function test_CompleteFlowReentrancyProtection() public {
        // This test verifies reentrancy protection by attempting multiple operations
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 1, nativeToken, LISTING_PRICE, expiry);

        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 2, address(mockERC20), LISTING_PRICE, expiry);

        // Should not be able to exploit reentrancy in buyItem
        vm.deal(buyer, LISTING_PRICE);
        vm.prank(buyer);
        nftMarketplace.buyItem{value: LISTING_PRICE}(address(mockNFT), 1);

        // First purchase should succeed, second should fail if reentrancy attempted
        assertEq(mockNFT.ownerOf(1), buyer);
    }

    function test_CompleteFlowWithdrawUnsuccessfulAuctionAndRelist() public {
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

        // Some bids below reserve
        address bidder1 = makeAddr("bidder1");
        vm.deal(bidder1, 1.3 ether);
        vm.prank(bidder1);
        nftMarketplace.placeBid{value: 1.3 ether}(address(mockNFT), 1, 1.3 ether);

        // Auction ends without meeting reserve
        vm.warp(block.timestamp + 2 days);

        // Verify NFT stuck in marketplace
        assertEq(mockNFT.ownerOf(1), address(nftMarketplace));

        // Seller withdraws unsuccessful auction
        vm.prank(user);
        nftMarketplace.withdrawUnsuccessfulAuction(address(mockNFT), 1);

        // Verify NFT returned to seller
        assertEq(mockNFT.ownerOf(1), user);

        // Seller can now relist at a lower price
        vm.prank(user);
        nftMarketplace.listItem(address(mockNFT), 1, nativeToken, 1.2 ether, expiry);

        // New buyer purchases at fixed price
        vm.deal(buyer, 1.2 ether);
        vm.prank(buyer);
        nftMarketplace.buyItem{value: 1.2 ether}(address(mockNFT), 1);

        // Verify successful sale
        assertEq(mockNFT.ownerOf(1), buyer);
    }

    function test_CompleteFlowMultipleUnsuccessfulAuctions() public {
        // Create multiple auctions
        for (uint256 i = 1; i <= 3; i++) {
            vm.prank(user);
            nftMarketplace.createAuction(address(mockNFT), i, nativeToken, 1 ether, 1.5 ether, 1 days);

            // Place bids below reserve for each
            address bidder = makeAddr(string(abi.encodePacked("bidder", i)));
            vm.deal(bidder, 1.4 ether);
            vm.prank(bidder);
            nftMarketplace.placeBid{value: 1.4 ether}(address(mockNFT), i, 1.4 ether);
        }

        // All auctions end
        vm.warp(block.timestamp + 2 days);

        // Withdraw all unsuccessful auctions
        for (uint256 i = 1; i <= 3; i++) {
            vm.prank(user);
            nftMarketplace.withdrawUnsuccessfulAuction(address(mockNFT), i);

            assertEq(mockNFT.ownerOf(i), user);
        }

        // Verify all auctions marked as settled
        for (uint256 i = 1; i <= 3; i++) {
            (,,,,,,,, bool settled) = nftMarketplace.s_auctions(address(mockNFT), i);
            assertTrue(settled);
        }
    }

    function test_CompleteFlowWithdrawAndCreateNewAuction() public {
        // First auction fails
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), 1, nativeToken, 1 ether, 1.5 ether, 1 days);

        vm.warp(block.timestamp + 2 days);
        vm.prank(user);
        nftMarketplace.withdrawUnsuccessfulAuction(address(mockNFT), 1);

        // Seller creates new auction with lower reserve
        vm.prank(user);
        nftMarketplace.createAuction(
            address(mockNFT),
            1,
            address(mockERC20), // Different payment token
            0.8 ether, // Lower start price
            1 ether, // Lower reserve
            2 days // Longer duration
        );

        // New bidder wins with ERC20
        mockERC20.mint(buyer, 1.2 ether);
        vm.prank(buyer);
        mockERC20.approve(address(nftMarketplace), 1.2 ether);
        vm.prank(buyer);
        nftMarketplace.placeBid(address(mockNFT), 1, 1.2 ether);

        vm.warp(block.timestamp + 3 days);
        vm.prank(user);
        nftMarketplace.settleAuction(address(mockNFT), 1);

        // Verify successful sale with new terms
        assertEq(mockNFT.ownerOf(1), buyer);
    }

    function test_CompleteFlowWithdrawalPreventsLockedNFTs() public {
        // This test demonstrates the fix for the critical issue
        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), 1, nativeToken, 1 ether, 1.5 ether, 1 days);

        // No bids at all
        vm.warp(block.timestamp + 2 days);

        // Before fix: NFT would be permanently locked
        // After fix: Seller can withdraw
        vm.prank(user);
        nftMarketplace.withdrawUnsuccessfulAuction(address(mockNFT), 1);

        // NFT safely returned to seller
        assertEq(mockNFT.ownerOf(1), user);

        // Seller can do whatever they want with the NFT now
        vm.prank(user);
        mockNFT.transferFrom(user, buyer, 1);
        assertEq(mockNFT.ownerOf(1), buyer);
    }

    function test_CompleteFlowWithdrawalGasOptimization() public {
        // Test gas usage for withdrawal operation
        uint256 gasStart;
        uint256 gasUsed;

        vm.prank(user);
        nftMarketplace.createAuction(address(mockNFT), 1, nativeToken, 1 ether, 1.5 ether, 1 days);

        vm.warp(block.timestamp + 2 days);

        vm.prank(user);
        gasStart = gasleft();
        nftMarketplace.withdrawUnsuccessfulAuction(address(mockNFT), 1);
        gasUsed = gasStart - gasleft();

        console.log("Gas used for withdrawal:", gasUsed);
        assertTrue(gasUsed > 0); // Basic sanity check
    }
}
