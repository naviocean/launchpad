// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./../../interfaces/IERC20Extented.sol";

interface SharedConstants {
    enum SaleRoundTypes {
        ALLOCATION,
        FCFS
    }

    enum Statuses {
        COMMING,
        FINZALIZE,
        CANCELLED,
        OPENING
    }

    enum UnsoldToken {
        BURN,
        REFUND
    }

    enum PresaleType {
        PUBLIC,
        WHITELIST,
        BLABLA
    }

    struct SaleRound {
        uint256 startAt;
        uint256 endtAt;
        SaleRoundTypes saleType;
    }

    struct RegistrationInfo {
        string id;
        bool isRegister;
        uint256 poolWeight;
    }

    struct VestingTimeline {
        uint256[] percents;
        uint256[] timestamps; // seconds
    }

    struct VestingHistory {
        uint8 index; // index of vesting timeline
        uint256 amount;
        uint256 claimAt; // seconds
    }

    struct TimeRound {
        uint256 startAt;
        uint256 endAt; // seconds
    }

    struct LaunchpadData {
        /* Token */
        IERC20Extented token;
        IERC20Extented payInToken;
        UnsoldToken unsoldToken;
        PresaleType presaleType;
        /* Sorf and Hard cap */
        uint256 softCap;
        uint256 hardCap;
        /* Presale time */
        TimeRound register;
        TimeRound allocation;
        TimeRound fcfs;
        /* Rate */
        uint256 presaleRate;
        /* Base Allocation */
        uint256 baseAllocation; // BUSD
    }
}
