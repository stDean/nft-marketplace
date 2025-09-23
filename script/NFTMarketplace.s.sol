// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";
import {NFTMarketplace} from "src/NFTMarketplace.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployNFTMarketplace is Script {
    function run() external returns (NFTMarketplace, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        vm.startBroadcast();

        NFTMarketplace nftMarketplace = new NFTMarketplace();

        vm.stopBroadcast();

        return (nftMarketplace, helperConfig);
    }
}
