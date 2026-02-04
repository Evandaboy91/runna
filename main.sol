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
