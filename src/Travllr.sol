// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Travllr
 * @dev A smart contract for a travel-to-earn platform where users can create tours, upvote tours, and check in to locations. 
 *      Users are rewarded points for creating tours and checking in to existing tours. 
 *      This contract incentivizes travel and location verification through community participation and point rewards.
 * @author Victor
 */
contract Travllr {
    /// @notice Reverts when a tourId that does not exist is called.
    error Travllr__tourDoesNotExist();

    /// @notice Reverts when users who check in enter a wrong location.
    error Travllr__locationMismatch();

    /// @notice Reverts if the tour owner tries to upvote their own tour.
    error Travllr__ownerCannotUpvote();

    /// @notice Reverts if a user tries to upvote a tour they have already upvoted.
    error Travllr__alreadyUpvoted();

    /// @notice Reverts if the tour owner tries to check in to their own tour.
    error Travllr__ownerCannotCheckIn();

    /// @notice Reverts if a user tries to check in to the same tour more than once.
    error Travllr__alreadyCheckedIn();

     /// @notice Reverts if a user does not have at least 1 ether balance to upvote.
    error Travllr__insufficientEtherBalance();

    struct Tour {
        address creator;      // The address of the user who created the tour
        string imageHash;     // IPFS hash of the image representing the tour location
        string location;      // Exact location, e.g., latitude/longitude in string format
        uint256 upvotes;      // Number of upvotes from other users
        bool isVerified;      // Status indicating if the tour has been verified through upvotes
    }

    struct CheckIn {
        address user;         // Address of the user who checked in
        string imageHash;     // IPFS hash for the check-in image proof
        string location;      // Location provided by the user during check-in
        bool isCheckedIn;     // Status indicating if the check-in is valid
    }

    mapping(uint256 => Tour) public s_tours;               // Maps tour IDs to their Tour details
    mapping(uint256 => CheckIn[]) public s_checkIns;       // Maps tour IDs to arrays of CheckIns
    mapping(address => uint256) public s_points;           // Maps user addresses to their respective point balances
    mapping(uint256 => mapping(address => bool)) public s_upvoted; // Tracks if a user has upvoted a specific tour
    mapping(uint256 => mapping(address => bool)) public s_hasCheckedIn; // Tracks if a user has checked in for a specific tour

    uint256 public s_tourCount = 0;                        // Counter to keep track of total tours created
    uint256 public constant CHECK_IN_POINTS = 10;          // Points awarded for each check-in
    uint256 public constant CREATION_POINTS = 5;           // Points awarded to tour creator per valid check-in

    /// @notice Emitted when a new tour is created.
    /// @param tourId The unique ID of the tour created
    /// @param creator The address of the user who created the tour
    /// @param location The location string provided for the tour
    event TourCreated(
        uint256 indexed tourId,
        address indexed creator,
        string indexed location
    );

    /// @notice Emitted when a tour is upvoted.
    /// @param tourId The ID of the tour being upvoted
    /// @param voter The address of the user who upvoted the tour
    event TourUpvoted(uint256 indexed tourId, address indexed voter);

    /// @notice Emitted when a user successfully checks in at a tour location.
    /// @param tourId The ID of the tour where check-in occurred
    /// @param user The address of the user who checked in
    event CheckInConfirmed(uint256 indexed tourId, address indexed user);

    /// @notice Emitted when points are awarded to a user.
    /// @param user The address of the user receiving points
    /// @param points The number of points awarded
    event PointsAwarded(address indexed user, uint256 indexed points);

    /// @dev Modifier to ensure the tour with the given ID exists.
    /// @param tourId The ID of the tour to validate
    modifier tourExists(uint256 tourId) {
        if (tourId >= s_tourCount) {
            revert Travllr__tourDoesNotExist();
        }
        _;
    }

    /**
     * @notice Allows a user to create a new tour with an image and location.
     * @param _imageHash The IPFS hash of the tour's image
     * @param _location The exact location for the tour
     * @dev This function increments the tour counter and adds the new tour to the mapping.
     */
    function createTour(string memory _imageHash, string memory _location) external {
        s_tours[s_tourCount] = Tour({
            creator: msg.sender,
            imageHash: _imageHash,
            location: _location,
            upvotes: 0,
            isVerified: false
        });
        emit TourCreated(s_tourCount, msg.sender, _location);
        s_tourCount++;
    }

    /**
     * @notice Allows users to upvote a tour, contributing to its verification.
     * @param _tourId The ID of the tour to be upvoted
     * @dev Reverts if the user is the creator of the tour, does not have enough ether balance or has already upvoted. 
     *      If a tour receives enough upvotes, it becomes verified. Adjust the upvote threshold as needed.
     */
    function upvoteTour(uint256 _tourId) external tourExists(_tourId) {
        Tour storage tour = s_tours[_tourId];
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

        tour.upvotes += 1;
        if (tour.upvotes >= 3) { // Adjust threshold as needed
            tour.isVerified = true;
        }
        emit TourUpvoted(_tourId, msg.sender);
    }

    /**
     * @notice Allows users to check in at a specified tour location to earn points.
     * @param _tourId The ID of the tour to check in to
     * @param _imageHash The IPFS hash of the check-in image proof
     * @param _location The location provided by the user during check-in
     * @dev Checks if the provided location matches the tour location, if the user has already checked in, and if the user is the tour owner. Awards points to both the tour creator and the visitor.
     */
    function checkIn(
        uint256 _tourId,
        string memory _imageHash,
        string memory _location
    ) external tourExists(_tourId) {
        Tour storage tour = s_tours[_tourId];

        if (msg.sender == tour.creator) {
            revert Travllr__ownerCannotCheckIn();
        }
        if (s_hasCheckedIn[_tourId][msg.sender]) {
            revert Travllr__alreadyCheckedIn();
        }
        if (
            keccak256(abi.encodePacked(_location)) !=
            keccak256(abi.encodePacked(tour.location))
        ) {
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

        s_points[tour.creator] += CREATION_POINTS;
        s_points[msg.sender] += CHECK_IN_POINTS;

        emit CheckInConfirmed(_tourId, msg.sender);
        emit PointsAwarded(tour.creator, CREATION_POINTS);
        emit PointsAwarded(msg.sender, CHECK_IN_POINTS);
    }

    /**
     * @notice Retrieves the point balance of a specific user.
     * @param _user The address of the user whose points balance is requested
     * @return The total points accumulated by the user
     */
    function getUserPoints(address _user) external view returns (uint256) {
        return s_points[_user];
    }

    /**
     * @notice Retrieves the check-ins for a specific tour.
     * @param _tourId The ID of the tour for which check-ins are requested
     * @return An array of CheckIn structs representing each check-in for the tour
     */
    function getCheckIns(uint256 _tourId)
        external
        view
        tourExists(_tourId)
        returns (CheckIn[] memory)
    {
        return s_checkIns[_tourId];
    }
}
