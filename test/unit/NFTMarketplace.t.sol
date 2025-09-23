// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;

import {Test, console} from "forge-std/Test.sol";
import {DeployNFTMarketplace, HelperConfig, NFTMarketplace} from "script/NFTMarketplace.s.sol";

contract NFTMarketplaceTest is Test {
    DeployNFTMarketplace deployer;
    HelperConfig helperConfig;
    NFTMarketplace nftMarketplace;
    HelperConfig.NetworkConfig config;

    function setUp() external {
        deployer = new DeployNFTMarketplace();
        (nftMarketplace, helperConfig) = deployer.run();
        config = helperConfig.getConfig();
    }

    // ========================== CONSTRUCTOR/INITIALIZATION TEST =============================
    function test_ConstructorRevertIFProtocolFeeTooHigh() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__FeeTooHigh.selector);
        new NFTMarketplace(5_000, config.treasury);
    }

    function test_ConstructorRevertIFTreasuryIsZeroAddress() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidTreasury.selector);
        new NFTMarketplace(config.protocolFee, address(0));
    }

    function test_ConstructorShouldInitializeCorrectly() public view {
        assertEq(nftMarketplace.s_treasury(), config.treasury);
        assertEq(nftMarketplace.s_protocolFee(), config.protocolFee);
        assertEq(nftMarketplace.getSupportedTokens().length, 1);
    }
}
