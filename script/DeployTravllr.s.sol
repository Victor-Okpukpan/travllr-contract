// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {Travllr} from "../src/Travllr.sol";

/**
 * @title DeployTravllr
 * @notice Deployment script for Travllr contract
 * @dev Uses Foundry's Script contract for deployment
 */
contract DeployTravllr is Script {
    // Default values for constructor parameters
    uint256 private constant CHECK_IN_POINTS = 100;
    uint256 private constant CREATION_POINTS = 50;
    uint256 private constant INITIAL_UPVOTE_THRESHOLD = 3;

    function run() external returns (Travllr) {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy Travllr contract with constructor parameters
        Travllr travllr = new Travllr(
            CHECK_IN_POINTS,
            CREATION_POINTS,
            INITIAL_UPVOTE_THRESHOLD,
            msg.sender
        );

        vm.stopBroadcast();
        return travllr;
    }
}
