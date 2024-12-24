// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Travllr
 * @dev A smart contract for a travel-to-earn platform where users can create tours, upvote tours, and check in to locations.
 *      Users are rewarded points for creating tours and checking in to existing tours.
 *      This contract incentivizes travel and location verification through community participation and point rewards.
 * @author Victor
 */
contract Travllr is Ownable, ReentrancyGuard, Pausable {
    /// @notice Reverts when a tourId that does not exist is called
    /// @dev Thrown when accessing a tour with an ID >= total tour count
    error Travllr__tourDoesNotExist();
    
    /// @notice Reverts when users who check in enter a wrong location
    /// @dev Thrown when check-in location hash doesn't match tour location hash
    error Travllr__locationMismatch();
    
    /// @notice Reverts if the tour owner tries to upvote their own tour
    /// @dev Prevents self-upvoting to maintain fair verification
    error Travllr__ownerCannotUpvote();
    
    /// @notice Reverts if a user tries to upvote a tour they have already upvoted
    /// @dev Prevents multiple upvotes from same address
    error Travllr__alreadyUpvoted();
    
    /// @notice Reverts if the tour owner tries to check in to their own tour
    /// @dev Prevents creators from earning check-in points on their own tours
    error Travllr__ownerCannotCheckIn();
    
    /// @notice Reverts if a user tries to check in to the same tour more than once
    /// @dev Prevents multiple check-ins to same tour
    error Travllr__alreadyCheckedIn();
    
    /// @notice Reverts if a user does not have at least 1 ether balance to upvote
    /// @dev Minimum balance requirement to prevent spam upvotes
    error Travllr__insufficientEtherBalance();
    
    /// @notice Reverts if a location has not been verified
    /// @dev Location must reach upvote threshold before check-ins
    error Travllr__locationIsNotVerified();
    
    /// @notice Reverts when input parameters are invalid
    /// @dev Input validation for empty strings and array length mismatches
    error Travllr__InvalidParameters();
    
    /// @notice Reverts when caller is not the tour creator
    /// @dev Access control for tour modification functions
    error Travllr__NotTourCreator();
    
    /// @notice Reverts when trying to update a verified tour
    /// @dev Prevents modifications to already verified tours
    error Travllr__CannotUpdateVerifiedTour();

    /**
     * @notice Structure containing all tour information
     * @param creator Address of tour creator
     * @param imageHash IPFS hash of tour image
     * @param location String representation of location
     * @param upvotes Number of upvotes received
     * @param isVerified Whether tour is verified through upvotes
     * @param isActive Whether tour is currently active
     */
    struct Tour {
        address creator;
        string imageHash;
        string location;
        uint256 upvotes;
        bool isVerified;
        bool isActive;
    }

    /**
     * @notice Structure containing check-in information
     * @param user Address of user checking in
     * @param imageHash IPFS hash of check-in image
     * @param location String representation of check-in location
     * @param isCheckedIn Boolean confirming successful check-in
     */
    struct CheckIn {
        address user;
        string imageHash;
        string location;
        bool isCheckedIn;
    }

    /// @notice Mapping from tour ID to Tour struct
    mapping(uint256 => Tour) public s_tours;
    
    /// @notice Mapping from tour ID to array of CheckIn structs
    mapping(uint256 => CheckIn[]) public s_checkIns;
    
    /// @notice Mapping from user address to their point balance
    mapping(address => uint256) public s_points;
    
    /// @notice Mapping from tour ID and user address to upvote status
    mapping(uint256 => mapping(address => bool)) public s_upvoted;
    
    /// @notice Mapping from tour ID and user address to check-in status
    mapping(uint256 => mapping(address => bool)) public s_hasCheckedIn;

    /// @notice Total number of tours created
    uint256 public s_tourCount = 0;
    
    /// @notice Points awarded for checking in to a tour
    uint256 public immutable i_checkInPoints;
    
    /// @notice Points awarded to tour creator when someone checks in
    uint256 public immutable i_creationPoints;
    
    /// @notice Number of upvotes required for tour verification
    uint256 public s_upvoteThreshold;

    /// @notice Emitted when a new tour is created
    event TourCreated(uint256 indexed tourId, address indexed creator, string indexed location);
    
    /// @notice Emitted when a tour receives an upvote
    event TourUpvoted(uint256 indexed tourId, address indexed voter);
    
    /// @notice Emitted when a user successfully checks in to a tour
    event CheckInConfirmed(uint256 indexed tourId, address indexed user);
    
    /// @notice Emitted when points are awarded to a user
    event PointsAwarded(address indexed user, uint256 indexed points);
    
    /// @notice Emitted when a tour is updated
    event TourUpdated(uint256 indexed tourId, string newImageHash, string newLocation);
    
    /// @notice Emitted when upvote threshold is changed
    event ThresholdUpdated(uint256 newThreshold);
    
    /// @notice Emitted when a tour is deactivated
    event TourDeactivated(uint256 indexed tourId);

    /**
     * @notice Contract constructor
     * @param checkInPoints Points awarded for checking in
     * @param creationPoints Points awarded to creator per check-in
     * @param initialUpvoteThreshold Initial threshold for tour verification
     */
    constructor(
        uint256 checkInPoints,
        uint256 creationPoints,
        uint256 initialUpvoteThreshold,
        address owner
    ) Ownable(owner) {
        i_checkInPoints = checkInPoints;
        i_creationPoints = creationPoints;
        s_upvoteThreshold = initialUpvoteThreshold;
    }

    /**
     * @notice Modifier to check if tour exists
     * @param tourId ID of tour to check
     */
    modifier tourExists(uint256 tourId) {
        if (tourId >= s_tourCount) {
            revert Travllr__tourDoesNotExist();
        }
        _;
    }

    /**
     * @notice Modifier to restrict access to tour creator
     * @param tourId ID of tour to check
     */
    modifier onlyTourCreator(uint256 tourId) {
        if (msg.sender != s_tours[tourId].creator) {
            revert Travllr__NotTourCreator();
        }
        _;
    }

    /**
     * @notice Creates a new tour
     * @param _imageHash IPFS hash of tour image
     * @param _location String representation of tour location
     * @dev Emits TourCreated event
     */
    function createTour(string memory _imageHash, string memory _location) external whenNotPaused {
        if (bytes(_imageHash).length == 0 || bytes(_location).length == 0) {
            revert Travllr__InvalidParameters();
        }

        s_tours[s_tourCount] = Tour({
            creator: msg.sender,
            imageHash: _imageHash,
            location: _location,
            upvotes: 0,
            isVerified: false,
            isActive: true
        });

        emit TourCreated(s_tourCount, msg.sender, _location);
        s_tourCount++;
    }

    /**
     * @notice Updates an existing unverified tour
     * @param _tourId ID of tour to update
     * @param _newImageHash New IPFS hash of tour image
     * @param _newLocation New location string
     * @dev Can only be called by tour creator and only for unverified tours
     */
    function updateTour(
        uint256 _tourId,
        string memory _newImageHash,
        string memory _newLocation
    ) external tourExists(_tourId) onlyTourCreator(_tourId) whenNotPaused {
        Tour storage tour = s_tours[_tourId];
        
        if (tour.isVerified) {
            revert Travllr__CannotUpdateVerifiedTour();
        }
        if (bytes(_newImageHash).length == 0 || bytes(_newLocation).length == 0) {
            revert Travllr__InvalidParameters();
        }

        tour.imageHash = _newImageHash;
        tour.location = _newLocation;

        emit TourUpdated(_tourId, _newImageHash, _newLocation);
    }

    /**
     * @notice Allows users to upvote a tour
     * @param _tourId ID of tour to upvote
     * @dev Requires minimum balance and prevents duplicate votes
     */
    function upvoteTour(uint256 _tourId) external tourExists(_tourId) whenNotPaused {
        Tour storage tour = s_tours[_tourId];
        if (!tour.isActive) {
            revert Travllr__tourDoesNotExist();
        }
        if (msg.sender == tour.creator) {
            revert Travllr__ownerCannotUpvote();
        }
        if (s_upvoted[_tourId][msg.sender]) {
            revert Travllr__alreadyUpvoted();
        }
        if (msg.sender.balance < 1 ether) {
            revert Travllr__insufficientEtherBalance();
        }
        s_upvoted[_tourId][msg.sender] = true;

        tour.upvotes++;
        if (tour.upvotes >= s_upvoteThreshold) {
            tour.isVerified = true;
        }
        emit TourUpvoted(_tourId, msg.sender);
    }

    /**
     * @notice Allows users to check in to a verified tour
     * @param _tourId ID of tour to check in to
     * @param _imageHash IPFS hash of check-in image
     * @param _location String representation of check-in location
     * @dev Verifies location match and prevents duplicate check-ins
     */
    function checkIn(
        uint256 _tourId,
        string memory _imageHash,
        string memory _location
    ) public tourExists(_tourId) whenNotPaused nonReentrant {
        Tour storage tour = s_tours[_tourId];
        if (!tour.isActive) {
            revert Travllr__tourDoesNotExist();
        }
        if (tour.isVerified != true) {
            revert Travllr__locationIsNotVerified();
        }
        if (msg.sender == tour.creator) {
            revert Travllr__ownerCannotCheckIn();
        }
        if (s_hasCheckedIn[_tourId][msg.sender]) {
            revert Travllr__alreadyCheckedIn();
        }
        if (keccak256(abi.encodePacked(_location)) != keccak256(abi.encodePacked(tour.location))) {
            revert Travllr__locationMismatch();
        }

        s_hasCheckedIn[_tourId][msg.sender] = true;

        s_checkIns[_tourId].push(
            CheckIn({
                user: msg.sender,
                imageHash: _imageHash,
                location: _location,
                isCheckedIn: true
            })
        );

        s_points[tour.creator] += i_creationPoints;
        s_points[msg.sender] += i_checkInPoints;

        emit CheckInConfirmed(_tourId, msg.sender);
        emit PointsAwarded(tour.creator, i_creationPoints);
        emit PointsAwarded(msg.sender, i_checkInPoints);
    }

    /**
     * @notice Allows tour creator to deactivate their tour
     * @param _tourId ID of tour to deactivate
     */
    function deactivateTour(uint256 _tourId) 
        external 
        tourExists(_tourId) 
        onlyTourCreator(_tourId) 
        whenNotPaused 
    {
        s_tours[_tourId].isActive = false;
        emit TourDeactivated(_tourId);
    }

    /**
     * @notice Allows owner to update upvote threshold
     * @param _newThreshold New threshold value
     */
    function setUpvoteThreshold(uint256 _newThreshold) external onlyOwner {
        s_upvoteThreshold = _newThreshold;
        emit ThresholdUpdated(_newThreshold);
    }

    /**
     * @notice Pauses all contract operations
     * @dev Can only be called by owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses contract operations
     * @dev Can only be called by owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Gets points balance for a user
     * @param _user Address of user
     * @return uint256 Point balance
     */
    function getUserPoints(address _user) external view returns (uint256) {
        return s_points[_user];
    }

    /**
     * @notice Gets all check-ins for a tour
     * @param _tourId ID of tour
     * @return CheckIn[] Array of check-ins
     */
    function getCheckIns(uint256 _tourId) 
        external 
        view 
        tourExists(_tourId) 
        returns (CheckIn[] memory) 
    {
        return s_checkIns[_tourId];
    }

    /**
     * @notice Gets detailed information about a tour
     * @param _tourId ID of tour
     * @return creator Address of tour creator
     * @return imageHash IPFS hash of tour image
     * @return location Tour location string
     * @return upvotes Number of upvotes
     * @return isVerified Verification status
     * @return isActive Active status
     */
    function getTourDetails(uint256 _tourId)
        external
        view
        tourExists(_tourId)
        returns (
            address creator,
            string memory imageHash,
            string memory location,
            uint256 upvotes,
            bool isVerified,
            bool isActive
        )
    {
        Tour storage tour = s_tours[_tourId];
        return (
            tour.creator,
            tour.imageHash,
            tour.location,
            tour.upvotes,
            tour.isVerified,
            tour.isActive
        );
    }
}
