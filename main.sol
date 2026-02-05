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
        _;
    }

    constructor() {
        baseChainId = 8453;
        curator = msg.sender;
        genesisBlock = block.number;
        contractSeal = keccak256(
            abi.encodePacked(
                block.prevrandao,
                block.chainid,
                block.timestamp,
                msg.sender,
                "runna.meridian.2847.v1"
            )
        );
        trackCount = 7;
        maxStamina = 96;
        staminaPerLap = 12;
        minLapDistance = 400;
        seasonDurationBlocks = 604800;
        medalThresholdMeters = 10000;

        tracks[0] = Track({ exists: true, lapLengthMeters: 400, index: 0 });
        tracks[1] = Track({ exists: true, lapLengthMeters: 800, index: 1 });
        tracks[2] = Track({ exists: true, lapLengthMeters: 1600, index: 2 });
        tracks[3] = Track({ exists: true, lapLengthMeters: 3200, index: 3 });
        tracks[4] = Track({ exists: true, lapLengthMeters: 5000, index: 4 });
        tracks[5] = Track({ exists: true, lapLengthMeters: 10000, index: 5 });
        tracks[6] = Track({ exists: true, lapLengthMeters: 21097, index: 6 });

        currentSeasonId = 1;
        seasons[1] = Season({
            startBlock: block.number,
            endBlock: block.number + seasonDurationBlocks,
            runnerCount: 0,
            finalized: false
        });
        emit SeasonStarted(1, block.number);
    }

    function runna() external view returns (string memory) {
        return "runna";
    }

    function register() external whenNotPaused {
        if (runners[msg.sender].registered) revert AlreadyRegistered();
        Season storage s = seasons[currentSeasonId];
        if (block.number >= s.endBlock || s.finalized) revert SeasonNotActive();

        runners[msg.sender] = Runner({
            registered: true,
            totalMeters: 0,
            lapCount: 0,
            stamina: maxStamina,
            lastLapBlock: 0,
            bestLapMeters: 0,
            medals: 0,
            joinedSeason: currentSeasonId
        });
        totalRunners += 1;
        _runnerList.push(msg.sender);
        seasonRunners[currentSeasonId].push(msg.sender);
        s.runnerCount += 1;
        seasonMeters[currentSeasonId][msg.sender] = 0;
        emit RunnerRegistered(msg.sender, currentSeasonId);
    }

    function completeLap(uint256 trackId, uint256 meters) external whenNotPaused {
        Runner storage r = runners[msg.sender];
        if (!r.registered) revert RunnerNotRegistered();
        if (trackId >= trackCount || !tracks[trackId].exists) revert InvalidTrack();
        if (r.stamina < staminaPerLap) revert InsufficientStamina();
        if (meters < minLapDistance || meters < tracks[trackId].lapLengthMeters) revert LapTooShort();

        Season storage s = seasons[currentSeasonId];
        if (block.number >= s.endBlock || s.finalized) revert SeasonNotActive();

        uint256 lapIndex = runnerLapCount[msg.sender];
        runnerLaps[msg.sender][lapIndex] = LapRecord({
            blockNumber: block.number,
            timestamp: block.timestamp,
            meters: meters,
            trackId: trackId
        });
        runnerLapCount[msg.sender] = lapIndex + 1;

        r.totalMeters += meters;
        r.lapCount += 1;
        r.lastLapBlock = block.number;
        r.stamina -= staminaPerLap;
        if (meters > r.bestLapMeters) r.bestLapMeters = meters;
        seasonMeters[currentSeasonId][msg.sender] += meters;

        if (r.totalMeters >= medalThresholdMeters && (r.totalMeters - meters) < medalThresholdMeters) {
            r.medals += 1;
            emit MedalAwarded(msg.sender, r.medals);
        }

        emit LapCompleted(msg.sender, trackId, meters, block.number);
    }

    function restoreStamina() external whenNotPaused {
        Runner storage r = runners[msg.sender];
        if (!r.registered) revert RunnerNotRegistered();
        uint256 blocksSinceLastLap = block.number - r.lastLapBlock;
        uint256 blocksPerStamina = 120;
        if (blocksSinceLastLap >= blocksPerStamina && r.stamina < maxStamina) {
            uint256 gain = blocksSinceLastLap / blocksPerStamina;
            if (r.stamina + gain > maxStamina) gain = maxStamina - r.stamina;
            r.stamina += gain;
            emit StaminaRestored(msg.sender, r.stamina);
        }
    }

    function startNewSeason() external onlyCurator {
        Season storage prev = seasons[currentSeasonId];
        if (!prev.finalized && block.number < prev.endBlock) revert SeasonNotActive();
        currentSeasonId += 1;
        seasons[currentSeasonId] = Season({
            startBlock: block.number,
            endBlock: block.number + seasonDurationBlocks,
            runnerCount: 0,
            finalized: false
        });
        emit SeasonStarted(currentSeasonId, block.number);
    }

    function finalizeSeason(uint256 seasonId) external onlyCurator {
        Season storage s = seasons[seasonId];
        if (s.finalized) revert SeasonAlreadyFinalized();
        if (block.number < s.endBlock) revert SeasonNotActive();
        s.finalized = true;
        emit SeasonFinalized(seasonId);
    }

    function setPaused(bool _paused) external onlyCurator {
        paused = _paused;
        emit PauseToggled(_paused);
    }

    function getRunner(address runner) external view returns (
        bool registered,
        uint256 totalMeters,
        uint256 lapCount,
        uint256 stamina,
        uint256 lastLapBlock,
        uint256 bestLapMeters,
        uint256 medals,
        uint256 joinedSeason
    ) {
        Runner storage r = runners[runner];
        return (
            r.registered,
            r.totalMeters,
            r.lapCount,
            r.stamina,
            r.lastLapBlock,
            r.bestLapMeters,
            r.medals,
            r.joinedSeason
        );
    }

    function getRunnerLap(address runner, uint256 lapIndex) external view returns (
        uint256 blockNumber,
        uint256 timestamp,
        uint256 meters,
        uint256 trackId
    ) {
        LapRecord storage lr = runnerLaps[runner][lapIndex];
        return (lr.blockNumber, lr.timestamp, lr.meters, lr.trackId);
    }

    function getSeason(uint256 seasonId) external view returns (
        uint256 startBlock,
        uint256 endBlock,
        uint256 runnerCount,
        bool finalized
    ) {
        Season storage s = seasons[seasonId];
        return (s.startBlock, s.endBlock, s.runnerCount, s.finalized);
    }

    function getSeasonRunnerCount(uint256 seasonId) external view returns (uint256) {
        return seasonRunners[seasonId].length;
    }

    function getSeasonRunnerAt(uint256 seasonId, uint256 index) external view returns (address) {
        return seasonRunners[seasonId][index];
    }

    function getSeasonMeters(uint256 seasonId, address runner) external view returns (uint256) {
        return seasonMeters[seasonId][runner];
    }

    function trackName(uint256 trackId) external pure returns (string memory) {
        if (trackId == 0) return "MeridianOval";
        if (trackId == 1) return "ZephyrLoop";
        if (trackId == 2) return "CoralMile";
        if (trackId == 3) return "ObsidianTwoMile";
        if (trackId == 4) return "MossFiveK";
        if (trackId == 5) return "AuroraTenK";
        if (trackId == 6) return "HalfMarathonSpine";
        return "";
    }

    function trackLength(uint256 trackId) external view returns (uint256) {
        if (trackId >= trackCount) return 0;
        return tracks[trackId].lapLengthMeters;
    }

    function runnerCount() external view returns (uint256) {
        return _runnerList.length;
    }

    function runnerAt(uint256 index) external view returns (address) {
        return _runnerList[index];
    }

    uint256 public constant MAX_LEADERBOARD_SIZE = 50;

    function leaderboardByMeters(uint256 seasonId, uint256 limit) external view returns (address[] memory, uint256[] memory) {
        uint256 n = seasonRunners[seasonId].length;
        if (n == 0) return (new address[](0), new uint256[](0));
        if (limit == 0 || limit > MAX_LEADERBOARD_SIZE) limit = MAX_LEADERBOARD_SIZE;
        if (limit > n) limit = n;
        address[] memory addrs = new address[](limit);
        uint256[] memory meters = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            addrs[i] = seasonRunners[seasonId][i];
            meters[i] = seasonMeters[seasonId][addrs[i]];
        }
        for (uint256 i = 0; i < limit; i++) {
            for (uint256 j = i + 1; j < limit; j++) {
                if (meters[j] > meters[i]) {
                    (addrs[i], addrs[j]) = (addrs[j], addrs[i]);
                    (meters[i], meters[j]) = (meters[j], meters[i]);
                }
            }
        }
        return (addrs, meters);
    }

    function canRun(address runner) external view returns (bool) {
        Runner storage r = runners[runner];
        if (!r.registered) return false;
        Season storage s = seasons[currentSeasonId];
        if (s.finalized || block.number >= s.endBlock) return false;
        return r.stamina >= staminaPerLap;
    }

    function contractInfo() external view returns (
        uint256 chainId,
        uint256 genesis,
        bytes32 seal,
        uint256 tracks,
        uint256 season
    ) {
        return (baseChainId, genesisBlock, contractSeal, trackCount, currentSeasonId);
    }

    function metersToNextMedal(address runner) external view returns (uint256) {
        Runner storage r = runners[runner];
        if (!r.registered) return medalThresholdMeters;
        uint256 nextThreshold = ((r.totalMeters / medalThresholdMeters) + 1) * medalThresholdMeters;
        return nextThreshold - r.totalMeters;
    }

    function staminaBlocksRemaining(address runner) external view returns (uint256) {
        Runner storage r = runners[runner];
        if (!r.registered || r.stamina >= maxStamina) return 0;
        uint256 blocksPerStamina = 120;
        uint256 needed = maxStamina - r.stamina;
        return needed * blocksPerStamina;
    }

    function isTrackValid(uint256 trackId) external view returns (bool) {
        return trackId < trackCount && tracks[trackId].exists;
    }

    function seasonIsActive(uint256 seasonId) external view returns (bool) {
        Season storage s = seasons[seasonId];
        return !s.finalized && block.number >= s.startBlock && block.number < s.endBlock;
    }

    function runnerLapsLength(address runner) external view returns (uint256) {
        return runnerLapCount[runner];
    }

    function meridianRelayVersion() external pure returns (bytes32) {
        return keccak256("runna.meridian.2847.v1");
    }

    function trackIds() external pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](7);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;
        ids[3] = 3;
        ids[4] = 4;
        ids[5] = 5;
        ids[6] = 6;
        return ids;
    }

    function config() external view returns (
        uint256 _maxStamina,
