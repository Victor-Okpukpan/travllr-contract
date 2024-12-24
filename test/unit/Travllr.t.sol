// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Travllr} from "../../src/Travllr.sol";
import {DeployTravllr} from "../../script/DeployTravllr.s.sol";

contract TravllrTest is Test {
    Travllr public travllr;
    address public owner;
    address public user1;
    address public user2;

    // Events to test
    event TourCreated(uint256 indexed tourId, address indexed creator, string indexed location);
    event TourUpvoted(uint256 indexed tourId, address indexed voter);
    event CheckInConfirmed(uint256 indexed tourId, address indexed user);
    event PointsAwarded(address indexed user, uint256 indexed points);

    function setUp() public {
        // First set owner address
        owner = makeAddr("owner");
        
        // Deploy contract
        DeployTravllr deployer = new DeployTravllr();
        travllr = deployer.run();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Fund test accounts
        vm.deal(user1, 2 ether);
        vm.deal(user2, 2 ether);
    }

    function test_CreateTour() public {
        vm.startPrank(user1);
        
        vm.expectEmit(true, true, true, true);
        emit TourCreated(0, user1, "Paris, France");
        
        travllr.createTour("QmHash1", "Paris, France");
        
        (
            address creator,
            string memory imageHash,
            string memory location,
            uint256 upvotes,
            bool isVerified,
            bool isActive
        ) = travllr.getTourDetails(0);
        
        assertEq(creator, user1);
        assertEq(imageHash, "QmHash1");
        assertEq(location, "Paris, France");
        assertEq(upvotes, 0);
        assertEq(isVerified, false);
        assertEq(isActive, true);
        
        vm.stopPrank();
    }

    function test_UpvoteTour() public {
        // First create a tour
        vm.prank(user1);
        travllr.createTour("QmHash1", "Paris, France");
        
        vm.startPrank(user2);
        
        vm.expectEmit(true, true, false, false);
        emit TourUpvoted(0, user2);
        
        travllr.upvoteTour(0);
        
        (,,, uint256 upvotes,,) = travllr.getTourDetails(0);
        assertEq(upvotes, 1);
        
        vm.stopPrank();
    }

    function test_CheckIn() public {
        // Create and verify tour
        vm.prank(user1);
        travllr.createTour("QmHash1", "Paris, France");
        
        // Get enough upvotes to verify
        for(uint i = 1; i <= 5; i++) {
            address voter = makeAddr(string(abi.encodePacked("voter", i)));
            vm.deal(voter, 2 ether);
            vm.prank(voter);
            travllr.upvoteTour(0);
        }
        
        vm.startPrank(user2);
        
        vm.expectEmit(true, true, false, false);
        emit CheckInConfirmed(0, user2);
        
        travllr.checkIn(0, "QmCheckInHash", "Paris, France");
        
        assertEq(travllr.getUserPoints(user2), 100); // CHECK_IN_POINTS
        assertEq(travllr.getUserPoints(user1), 50);  // CREATION_POINTS
        
        vm.stopPrank();
    }

    function testFail_InvalidTourId() public {
        vm.prank(user1);
        travllr.getTourDetails(999);
    }

    function testFail_DuplicateUpvote() public {
        vm.prank(user1);
        travllr.createTour("QmHash1", "Paris, France");
        
        vm.startPrank(user2);
        travllr.upvoteTour(0);
        travllr.upvoteTour(0); // Should fail
    }

    function testFail_CreatorUpvote() public {
        vm.startPrank(user1);
        travllr.createTour("QmHash1", "Paris, France");
        travllr.upvoteTour(0); // Should fail
    }

    function test_UpvoteAtThreshold() public {
        // Create a tour
        vm.prank(user1);
        travllr.createTour("QmHash1", "Paris, France");

        // Upvote to just below the threshold
        for (uint256 i = 1; i < 5; i++) {
            address voter = makeAddr(string(abi.encodePacked("voter", i)));
            vm.deal(voter, 2 ether);
            vm.prank(voter);
            travllr.upvoteTour(0);
        }

        // Verify it's not yet verified
        (, , , , bool isVerified, ) = travllr.getTourDetails(0);
        assertFalse(isVerified);

        // Upvote to reach the threshold
        address lastVoter = makeAddr("lastVoter");
        vm.deal(lastVoter, 2 ether);
        vm.prank(lastVoter);
        travllr.upvoteTour(0);

        // Verify it is now verified
        (, , , , isVerified, ) = travllr.getTourDetails(0);
        assertTrue(isVerified);
    }

    function testFail_UpdateVerifiedTour() public {
        // Create and verify a tour
        vm.prank(user1);
        travllr.createTour("QmHash1", "Paris, France");
        for (uint256 i = 1; i <= 5; i++) {
            address voter = makeAddr(string(abi.encodePacked("voter", i)));
            vm.deal(voter, 2 ether);
            vm.prank(voter);
            travllr.upvoteTour(0);
        }

        // Attempt to update the verified tour
        vm.prank(user1);
        travllr.updateTour(0, "QmNewHash", "New Location"); // Should fail
    }
} 