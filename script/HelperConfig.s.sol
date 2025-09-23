// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";

/**
 * @title CodeConstants
 * @notice Contains chain ID constants for different networks
 * @dev Used to identify which network the contract is deployed on
 */
contract CodeConstants {
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    // Add other chainIds as needed (e.g., MAINNET, POLYGON, etc.)
}

/**
 * @title HelperConfig
 * @notice Configuration helper for deploying NFTMarketplace across different networks
 * @dev Provides network-specific configuration parameters for protocol fees and treasury addresses
 */
contract HelperConfig is Script, CodeConstants {
    /**
     * @notice Network configuration structure
     * @param protocolFee The protocol fee in basis points (e.g., 500 = 5%)
     * @param treasury The address that will receive protocol fees
     */
    struct NetworkConfig {
        uint256 protocolFee;
        address treasury;
    }

    /// @notice Current active network configuration
    NetworkConfig private activeNetworkConfig;

    /// @notice Mapping of chain IDs to their respective network configurations
    mapping(uint256 => NetworkConfig) private networkConfigs;

    /// @notice Error thrown when an unsupported chain ID is encountered
    error HelperConfig__InvalidChainId();

    /**
     * @notice Constructor that initializes network configurations based on current chain ID
     * @dev Automatically sets up Sepolia or Local (Anvil) configurations on deployment
     */
    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            networkConfigs[SEPOLIA_CHAIN_ID] = getSepoliaNetworkConfig();
        } else if (block.chainid == LOCAL_CHAIN_ID) {
            networkConfigs[LOCAL_CHAIN_ID] = getOrCreateAnvilNetworkConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /**
     * @notice Get the current network configuration
     * @return NetworkConfig The configuration for the current network
     * @dev Falls back to creating Anvil config if on local chain and not initialized
     */
    function getConfig() external returns (NetworkConfig memory) {
        return getNetworkConfig(block.chainid);
    }

    /**
     * @notice Get network configuration for a specific chain ID
     * @param chainId The chain ID to get configuration for
     * @return NetworkConfig The configuration for the specified network
     * @dev Handles local chain deployment with lazy initialization
     */
    function getNetworkConfig(uint256 chainId) internal returns (NetworkConfig memory) {
        // Return cached configuration if available
        if (networkConfigs[chainId].treasury != address(0)) {
            return networkConfigs[chainId];
        }
        // Handle local chain deployment with lazy initialization
        else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilNetworkConfig();
        }
        // Revert for unsupported chains
        else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /**
     * @notice Get the predefined Sepolia testnet configuration
     * @return NetworkConfig Preconfigured settings for Sepolia network
     * @dev Uses fixed parameters optimized for testnet deployment
     */
    function getSepoliaNetworkConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            protocolFee: 500, // 5% protocol fee
            treasury: 0x17d4351aE801b0619ef914756A0423A83f10Af60 // Example treasury address
        });
    }

    /**
     * @notice Get or create Anvil local network configuration
     * @return NetworkConfig Configuration for local development
     * @dev Uses the default Anvil first account as treasury for testing
     */
    function getOrCreateAnvilNetworkConfig() internal returns (NetworkConfig memory) {
        // Return cached config if already created
        if (activeNetworkConfig.treasury != address(0)) return activeNetworkConfig;

        // Create new config for Anvil (using default first account)
        activeNetworkConfig = NetworkConfig({
            protocolFee: 500, // 5% protocol fee for testing
            treasury: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 // Default Anvil first account
        });

        return activeNetworkConfig;
    }
}
