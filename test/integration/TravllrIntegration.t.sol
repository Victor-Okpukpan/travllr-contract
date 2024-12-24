// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Travllr} from "../../src/Travllr.sol";
import {DeployTravllr} from "../../script/DeployTravllr.s.sol";

contract TravllrIntegrationTest is Test {
    Travllr public travllr;
    address public owner;
    address[] public users;
    uint256 public constant NUM_USERS = 10;

    function setUp() public {
        // First set owner address
        owner = makeAddr("owner");
        
        // Deploy contract
        DeployTravllr deployer = new DeployTravllr();
        
        travllr = deployer.run();

        // Create and fund test users
        for(uint256 i = 0; i < NUM_USERS; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            users.push(user);
            vm.deal(user, 2 ether);
        }
    }

    function test_CompleteUserJourney() public {
        // 1. First user creates multiple tours
        vm.startPrank(users[0]);
        string[3] memory locations = ["Paris, France", "London, UK", "Rome, Italy"];
        for(uint256 i = 0; i < locations.length; i++) {
            travllr.createTour(
                string(abi.encodePacked("QmHash", i)),
                locations[i]
            );
        }
        vm.stopPrank();

        // 2. Multiple users upvote the tours
        for(uint256 tourId = 0; tourId < locations.length; tourId++) {
            for(uint256 userId = 1; userId <= 5; userId++) {
                vm.prank(users[userId]);
                travllr.upvoteTour(tourId);
            }
        }

        // 3. Check that tours are verified
        for(uint256 tourId = 0; tourId < locations.length; tourId++) {
            (,,, uint256 upvotes, bool isVerified,) = travllr.getTourDetails(tourId);
            assertEq(upvotes, 5);
            assertTrue(isVerified);
        }

        // 4. Users check in to verified tours
        for(uint256 tourId = 0; tourId < locations.length; tourId++) {
            vm.prank(users[6]);
            travllr.checkIn(
                tourId,
                string(abi.encodePacked("QmCheckInHash", tourId)),
                locations[tourId]
            );
        }

        // 5. Verify points distribution
        uint256 creatorPoints = travllr.getUserPoints(users[0]);
        uint256 visitorPoints = travllr.getUserPoints(users[6]);
        
        assertEq(creatorPoints, 150); // 50 points * 3 check-ins
        assertEq(visitorPoints, 300); // 100 points * 3 check-ins
    }

    function test_PauseAndUnpause() public {
        // Start with owner
        vm.startPrank(address(this));
        travllr.pause();
        vm.stopPrank();
        
        // Try to create tour while paused (should fail)
        vm.expectRevert();
        vm.prank(users[0]);
        travllr.createTour("QmHash", "Paris, France");
        
        // Unpause with owner
        vm.startPrank(address(this));
        travllr.unpause();
        vm.stopPrank();
        
        // Should now succeed
        vm.prank(users[0]);
        travllr.createTour("QmHash", "Paris, France");
    }

    function test_UpdateAndDeactivateTour() public {
        // Create tour
        vm.prank(users[0]);
        travllr.createTour("QmHash", "Paris, France");
        
        // Update tour
        vm.prank(users[0]);
        travllr.updateTour(0, "QmNewHash", "Paris, France Updated");
        
        // Verify update
        (,string memory imageHash, string memory location,,,) = travllr.getTourDetails(0);
        assertEq(imageHash, "QmNewHash");
        assertEq(location, "Paris, France Updated");
        
        // Deactivate tour
        vm.prank(users[0]);
        travllr.deactivateTour(0);
        
        // Verify deactivation
        (,,,,, bool isActive) = travllr.getTourDetails(0);
        assertEq(isActive, false);
    }
} 