// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/erc20/IERC20.sol";
import "@openzeppelin/contracts/token/erc20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BHOStaking is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Stake(address indexed user, uint256 amount, uint256 duration);
    event Unstake(address indexed user, uint256 amount);
    event EmergencyUnstake(address indexed user, uint256 amount);
    event StakingPackageChange(StakingPackage[] indexed stakingPackages);
    event LevelChange(Level[] indexed levels);
    event EmergencyUnstakeFeeChange(uint256 indexed fee);

    uint256 public constant DECIMALS_PERCENT = 1e3;

    struct StakingPackage {
        string id;
        uint256 duration;
        uint256 apy;
    }

    struct Level {
        string id;
        uint256 minAmount;
        uint256 poolWeight;
    }

    struct UserInfo {
        uint256 amount; // current amount staked
        uint256 apy;
        uint256 stakedAt;
        uint256 unstakeAt; // time to user can unstake
        uint256 duration; // number of days packages
        uint256 lastAmoumt;
        uint256 lastStakedAt;
    }

    StakingPackage[] private stakingPackages;
    Level[] private levels;

    mapping(address => UserInfo) public usersInfo;

    // Emergency unstake fee
    uint256 public emergencyUnstakeFee;

    // The Staking token!
    IERC20 public bho;

    function initialize(IERC20 _bho) public initializer {
        bho = _bho;
        emergencyUnstakeFee = 10500; // 10.5%
        __Ownable_init();
    }

    /******************************************* Admin function below *******************************************/
    /**
     * @dev update staking packages
     */
    function updatePackages(StakingPackage[] memory _stakingPackages)
        external
        onlyOwner
    {
        delete stakingPackages;
        for (uint256 i = 0; i < _stakingPackages.length; i++) {
            require(_stakingPackages[i].apy > 0, "APY must be greater than 0");
            require(
                _stakingPackages[i].apy <= 100 * DECIMALS_PERCENT,
                "APY must be less than 100"
            );
            stakingPackages.push(
                StakingPackage(
                    _stakingPackages[i].id,
                    _stakingPackages[i].duration,
                    _stakingPackages[i].apy
                )
            );
        }
        emit StakingPackageChange(_stakingPackages);
    }

    /**
     * @dev update levels
     */
    function updateLevels(Level[] memory _levels) external onlyOwner {
        delete levels;
        for (uint256 i = 0; i < _levels.length; i++) {
            if (i == 0) {
                Level memory level0 = _levels[i];
                levels.push(
                    Level({
                        id: level0.id,
                        minAmount: level0.minAmount,
                        poolWeight: level0.poolWeight
                    })
                );
                continue;
            }
            Level memory levelCur = _levels[i];
            Level memory levelPre = _levels[i - 1];
            require(
                levelCur.minAmount > levelPre.minAmount,
                "Min amount of next level must be greater than previous level"
            );
            require(
                levelCur.poolWeight > levelPre.poolWeight,
                "PoolWeight of next level must be greater than previous level"
            );
            levels.push(levelCur);
        }
        emit LevelChange(_levels);
    }

    /**
     * @dev update emergency unstake fee
     */
    function updateEmergencyUnstakeFee(uint256 _emergencyUnstakeFee)
        external
        onlyOwner
    {
        require(_emergencyUnstakeFee <= 100 * DECIMALS_PERCENT, "Percent of fee invalid (100)");
        require(_emergencyUnstakeFee >= 0, "Percent of fee invalid (0)");
        emergencyUnstakeFee = _emergencyUnstakeFee;
        emit EmergencyUnstakeFeeChange(_emergencyUnstakeFee);
    }

    /******************************************* Participantr function below *******************************************/

    /**
     * @dev stake BHO with amount and id package
     */
    function stakeBHO(uint256 _amount, uint256 _pid)
        external
        returns (uint256 amount, uint256 duration)
    {
        require(_pid < stakingPackages.length, "Package invalid");
        require(_pid >= 0, "Package invalid (0)");
        require(_amount > 0, "Amount must be greater than 0");

        StakingPackage memory package = stakingPackages[_pid];
        address user = _msgSender();

        UserInfo memory userInfo = usersInfo[user];

        // transfer both capital and interest
        if (userInfo.amount > 0) {
            // both capital and interest
            uint256 pending = _pendingBHO(user);
            if (pending > 0) {
                if (block.timestamp > userInfo.unstakeAt) {
                    bho.transfer(user, pending);
                }
            }
            bho.transfer(user, userInfo.amount);
        }

        bho.transferFrom(user, address(this), _amount);

        uint256 stakedAt = block.timestamp;
        uint256 unstakeAt = stakedAt.add(package.duration);

        uint256 lastAmount = userInfo.amount;
        uint256 lastStakedAt = userInfo.stakedAt;

        usersInfo[user] = UserInfo({
            amount: _amount,
            apy: package.apy,
            stakedAt: stakedAt,
            unstakeAt: unstakeAt,
            duration: package.duration,
            lastAmoumt: lastAmount,
            lastStakedAt: lastStakedAt
        });

        emit Stake(user, _amount, package.duration);
        return (_amount, package.duration);
    }

    /**
     * @dev Emergency unstake with % fee
     */
    function emergencyUnstake() external {
        address user = _msgSender();
        UserInfo memory userInfo = usersInfo[user];
        require(userInfo.amount > 0, "Amount invalid");
        require(
            block.timestamp < userInfo.unstakeAt,
            "It is not time to emergency unstake"
        );
        uint256 percentInDecimals = 100 * DECIMALS_PERCENT;
        uint256 total = userInfo.amount.mul(percentInDecimals.sub(emergencyUnstakeFee)).div(percentInDecimals);
        bho.transfer(user, total);

        usersInfo[user] = UserInfo({
            amount: 0,
            apy: 0,
            stakedAt: 0,
            unstakeAt: 0,
            duration: 0,
            lastAmoumt: 0,
            lastStakedAt: 0
        });

        emit EmergencyUnstake(user, total);
    }

    /**
     * @dev Unstake BHO without fee
     */
    function unstakeBHO() external {
        address user = _msgSender();
        UserInfo memory userInfo = usersInfo[user];
        require(userInfo.amount > 0, "Amount invalid");
        require(
            block.timestamp > userInfo.unstakeAt,
            "It is not time to unstake"
        );

        uint256 pending = _pendingBHO(user);
        uint256 total = userInfo.amount.add(pending);

        bho.transfer(user, pending);
        bho.transfer(user, userInfo.amount);

        usersInfo[user] = UserInfo({
            amount: 0,
            apy: 0,
            stakedAt: 0,
            unstakeAt: 0,
            duration: 0,
            lastAmoumt: 0,
            lastStakedAt: 0
        });

        emit Unstake(user, total);
    }

    /******************************************* Common function below *******************************************/
    /**
     * @dev Get level of address
     */
    function levelOf(address _addr)
        external
        view
        returns (
            string memory id,
            uint256 minAmount,
            uint256 poolWeight
        )
    {
        UserInfo memory userInfo = usersInfo[_addr];
        uint256 index;
        for (uint256 i = 0; i < levels.length; i++) {
            Level memory _level = levels[i];
            if (userInfo.amount >= _level.minAmount) {
                index = i;
            }
        }
        Level memory level = levels[index];
        return (level.id, level.minAmount, level.poolWeight);
    }

    function packageLength() external view returns (uint256) {
        return stakingPackages.length;
    }

    function getStakingPackages() external view returns (StakingPackage[] memory) {
        return stakingPackages;
    }

    function levelLength() external view returns (uint256) {
        return levels.length;
    }

    function getLevels() external view returns (Level[] memory) {
        return levels;
    }

    function pendingBHO(address _user) external view returns (uint256) {
        return _pendingBHO(_user);
    }

    /******************************************* Test function below *******************************************/
    // function updateTime(
    //     address _user,
    //     uint256 _stakedAt,
    //     uint256 _unstakeAt
    // ) external {
    //     usersInfo[_user].stakedAt = _stakedAt;
    //     usersInfo[_user].unstakeAt = _unstakeAt;
    // }

    /******************************************* Internal function below *******************************************/
    function _pendingBHO(address _user) internal view returns (uint256) {
        UserInfo memory userInfo = usersInfo[_user];

        uint256 timestamp = block.timestamp;
        uint256 secondsUserStaked = timestamp.sub(userInfo.stakedAt);

        uint256 pending;
        if (secondsUserStaked > userInfo.duration) {
            pending = _calInterestBHO(
                userInfo.amount,
                userInfo.duration,
                userInfo.apy
            );
        } else {
            pending = _calInterestBHO(
                userInfo.amount,
                secondsUserStaked,
                userInfo.apy
            );
        }
        return pending;
    }

    function _convertSecondsToDays(uint256 _seconds)
        internal
        pure
        returns (uint256)
    {
        return _seconds.div(1 days);
    }

    function _calInterestBHO(
        uint256 _amount,
        uint256 _secondsStaked,
        uint256 _apy
    ) internal pure returns (uint256) {
        uint256 pending = _amount.mul(_secondsStaked).div(365 days);
        return pending.mul(_apy).div(100 * DECIMALS_PERCENT);
    }
}
