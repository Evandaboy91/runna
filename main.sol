// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Runna
/// @notice On-chain runner ledger for the 2847 Meridian Relay. Tracks splits, laps, finisher medals and season standings.
/// @dev Fixed at deployment for Base (chainId 8453). No proxy; all parameters set in constructor.

contract Runna {
    uint256 public immutable baseChainId;
    address public immutable curator;
    uint256 public immutable genesisBlock;
    bytes32 public immutable contractSeal;
    uint256 public immutable trackCount;
    uint256 public immutable maxStamina;
    uint256 public immutable staminaPerLap;
    uint256 public immutable minLapDistance;
    uint256 public immutable seasonDurationBlocks;
    uint256 public immutable medalThresholdMeters;

    bool public paused;
    uint256 public currentSeasonId;
    uint256 public totalRunners;

    struct Runner {
        bool registered;
        uint256 totalMeters;
        uint256 lapCount;
        uint256 stamina;
        uint256 lastLapBlock;
        uint256 bestLapMeters;
        uint256 medals;
        uint256 joinedSeason;
    }

    struct Track {
        bool exists;
        uint256 lapLengthMeters;
        uint256 index;
    }

    struct LapRecord {
        uint256 blockNumber;
        uint256 timestamp;
        uint256 meters;
        uint256 trackId;
    }

    struct Season {
        uint256 startBlock;
        uint256 endBlock;
        uint256 runnerCount;
        bool finalized;
    }

    mapping(address => Runner) public runners;
    mapping(uint256 => Track) public tracks;
    mapping(address => mapping(uint256 => LapRecord)) public runnerLaps;
    mapping(address => uint256) public runnerLapCount;
    mapping(uint256 => Season) public seasons;
    mapping(uint256 => address[]) public seasonRunners;
    mapping(uint256 => mapping(address => uint256)) public seasonMeters;
    address[] private _runnerList;

    event RunnerRegistered(address indexed runner, uint256 indexed seasonId);
    event LapCompleted(address indexed runner, uint256 trackId, uint256 meters, uint256 blockNum);
    event MedalAwarded(address indexed runner, uint256 totalMedals);
    event SeasonStarted(uint256 indexed seasonId, uint256 startBlock);
    event SeasonFinalized(uint256 indexed seasonId);
    event PauseToggled(bool paused);
    event StaminaRestored(address indexed runner, uint256 newStamina);

    error ContractPaused();
    error NotCurator();
    error RunnerNotRegistered();
    error InvalidTrack();
    error InsufficientStamina();
    error LapTooShort();
    error AlreadyRegistered();
    error SeasonNotActive();
    error SeasonAlreadyFinalized();

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyCurator() {
        if (msg.sender != curator) revert NotCurator();
