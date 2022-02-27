// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/erc20/IERC20.sol";
import "@openzeppelin/contracts/token/erc20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./../interfaces/IBHOStaking.sol";
import "./../libs/SharedConstants.sol";
import "./../../utils/Whitelist.sol";
import "./../../utils/SafeArrayUint.sol";

contract BHOLaunchpad is Ownable, Pausable, Whitelist, SharedConstants {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeArrayUint for uint256[];

    uint256 public constant DECIMALS_PERCENT = 1e3;
    uint256 public emergencyWithdrawFee = 10 * DECIMALS_PERCENT; // 90%

    address public FACTORY_ADDRESS;

    uint256 public percentCanBuyInFCFS = 25 * DECIMALS_PERCENT;

    address constant BURN_ADDRESS =
        address(0x000000000000000000000000000000000000dEaD);

    /* events */
    event EmergencyWithdraw(address indexed buyer, uint256 indexed amount);
    event EmergencyWithdrawFeeChange(uint256 indexed percent);
    event PercentBuyInFCFSChange(uint256 indexed percent);
    event BuyTokenInAllocationRound(
        address indexed buyer,
        uint256 indexed amount
    );
    event BuyTokenInAllocationFCFS(
        address indexed buyer,
        uint256 indexed amount
    );
    event ClaimToken(address indexed buyer, uint256 indexed amount);

    event WithdrawToken(address indexed buyer, uint256 indexed amount);
    event Contribute(address indexed buyer, uint256 indexed amount);
    event Register(address indexed addr);
    event UnRegister(address indexed addr);

    event StatusChange(Statuses indexed status);

    LaunchpadData private launchpadData;
    VestingTimeline private vestingTimeline;

    Statuses public status;

    IBHOStaking public staking;

    uint256 public capacity;
    uint256 public capacityAllocation;
    uint256 public capacityFCFS;
    mapping(address => uint256) private amountsInAllocation;
    mapping(address => uint256) private amountsInFCFS;

    mapping(address => VestingHistory[]) private vestingHistories;

    mapping(address => RegistrationInfo) private registrationList;

    /* Modifier */
    modifier checkWhoCanBuy() {
        // public
        if (launchpadData.presaleType == PresaleType.PUBLIC) {
            _;
            return;
        }

        // whitelist
        if (launchpadData.presaleType == PresaleType.WHITELIST) {
            require(
                isWhitelisted(_msgSender()),
                "Whitelist: address does not exist"
            );
            _;
            return;
        }
        require(
            registrationList[_msgSender()].isRegister,
            "Registration: Address dont register yet"
        );
        _;
    }
    modifier onlyFactoryAddress() {
        require(
            _msgSender() == FACTORY_ADDRESS,
            "Caller is not the factory address"
        );
        _;
    }

    constructor(
        LaunchpadData memory _launchpadData,
        VestingTimeline memory _vestingTimeline,
        IBHOStaking _stakingAddr,
        address _ownerAddr
    ) {
        // check time register, allocation, fcfs
        require(
            _launchpadData.register.startAt <= _launchpadData.register.endAt,
            "Register time invalid"
        );
        require(
            _launchpadData.register.endAt <= _launchpadData.allocation.startAt,
            "Register time must be before Allocation time"
        );

        require(
            _launchpadData.allocation.startAt <=
                _launchpadData.allocation.endAt,
            "Allocation time invalid"
        );
        require(
            _launchpadData.allocation.endAt <= _launchpadData.fcfs.startAt,
            "Allocation time must be before FCFS time"
        );

        require(
            _launchpadData.fcfs.startAt <= _launchpadData.fcfs.endAt,
            "FCFS time invalid"
        );

        require(
            _launchpadData.presaleRate > 0,
            "Presale rate must be greater than 0"
        );
        require(
            _vestingTimeline.percents.length ==
                _vestingTimeline.timestamps.length,
            "Vesting timeline invalid format"
        );
        require(
            _vestingTimeline.percents.sum() == (100 * DECIMALS_PERCENT),
            "Total percents must be equal 100"
        );

        launchpadData = _launchpadData;
        vestingTimeline = _vestingTimeline;
        FACTORY_ADDRESS = _msgSender();
        staking = _stakingAddr;
        transferOwnership(_ownerAddr);
    }

    /******************************************* Admin function below *******************************************/
    function collectTokenPayment(address _recipient) external onlyOwner {
        // Get 98% BUSD
        uint256 amountToken = capacity.mul(100).div(100);
        launchpadData.payInToken.transfer(owner(), amountToken);

        // Get remain BUSD include fee emergency withdraw
        launchpadData.payInToken.transfer(
            _recipient,
            launchpadData.payInToken.balanceOf(address(this))
        );
    }

    /******************************************* Owner function below *******************************************/
    /**
     * Update percent can buy in FCFS
     */
    function updatePercentCanBuyInFCFS(uint256 _percent) external onlyOwner {
        require(_percent > 0, "Percent be greater than 0");
        require(_percent <= 100 * DECIMALS_PERCENT, "Percent be less than 100");
        percentCanBuyInFCFS = _percent;

        emit PercentBuyInFCFSChange(_percent);
    }

    /**
     * Update emergencyWithdrawFee
     */
    function updateEmergencyWithdrawFee(uint256 _percent) external onlyOwner {
        require(_percent > 0, "Percent be greater than 0");
        require(_percent <= 100 * DECIMALS_PERCENT, "Percent be less than 100");
        emergencyWithdrawFee = _percent;

        emit EmergencyWithdrawFeeChange(_percent);
    }

    /**
     * Update status
     */
    function updateStatus(Statuses _status) external onlyOwner {
        status = _status;
    }

    /**
     * @dev update presale type : public, whitelist, ...
     */
    function updatePresaleType(PresaleType _presaleType) public onlyOwner {
        launchpadData.presaleType = _presaleType;
    }

    /**
     * @dev update presale type : public, whitelist, ...
     */
    function updateBaseAllocation(uint256 _baseAllocation) public onlyOwner {
        launchpadData.baseAllocation = _baseAllocation;
    }

    /**
     * @dev finalize launchpad
     */
    function finalize() public onlyOwner {
        require(status != Statuses.FINZALIZE, "Launchpad is finalized");
        require(status != Statuses.CANCELLED, "Launchpad is cancelled");

        _handleUnsoldToken();
        status = Statuses.FINZALIZE;

        emit StatusChange(Statuses.FINZALIZE);
    }

    /**
     * @dev cancel launchpad
     */
    function cancel() public onlyOwner {
        require(status != Statuses.CANCELLED, "Launchpad is cancelled");
        status = Statuses.CANCELLED;
        emit StatusChange(Statuses.CANCELLED);
    }

    /******************************************* Participant function below *******************************************/

    /**
     * User register
     */
    function register() public {
        // check time register round
        require(
            block.timestamp > launchpadData.register.startAt,
            "Register time dont start yet"
        );
        require(
            block.timestamp < launchpadData.register.endAt,
            "Register time expired"
        );
        address user = _msgSender();
        (string memory id, , uint256 poolWeight) = staking.levelOf(user);

        registrationList[user] = RegistrationInfo({
            id: id,
            poolWeight: poolWeight,
            isRegister: true
        });
        emit Register(user);
    }

    /**
     * User un register
     */
    function unregister() public {
        // check time register round
        require(
            block.timestamp > launchpadData.register.startAt,
            "Register time dont start yet"
        );
        require(
            block.timestamp < launchpadData.register.endAt,
            "Register time expired"
        );
        address user = _msgSender();
        registrationList[user] = RegistrationInfo({
            id: "",
            poolWeight: 0,
            isRegister: false
        });
        emit UnRegister(user);
    }

    /**
     * User un register
     */
    function registrationInfo(address _addr)
        public
        view
        returns (RegistrationInfo memory)
    {
        return registrationList[_addr];
    }

    /**
     * Buy token for Allocation round
     */
    function buyTokenAllocation(uint256 _amount) external checkWhoCanBuy {
        require(_amount > 0, "Amount must the greater than 0");
        require(status != Statuses.CANCELLED, "Launchpad is cancelled");
        require(status != Statuses.FINZALIZE, "Launchpad is finalized");
        // // check start, end time
        // require(block.timestamp < launchpadData.endAt, "Launchpad ended");
        // require(
        //     block.timestamp > launchpadData.startAt,
        //     "Launchpad do not start yet"
        // );
        // check hard cap
        require(
            capacity.add(_amount) <= launchpadData.hardCap,
            "The capacity has exceeded the limit"
        );
        // check time allocation round

        require(
            block.timestamp > launchpadData.allocation.startAt,
            "Allocation round dont start yet"
        );
        require(
            block.timestamp < launchpadData.allocation.endAt,
            "Allocation round expired"
        );

        // max BUSD user can buy
        address buyer = _msgSender();

        uint256 maxBuy = launchpadData.baseAllocation.mul(
            registrationList[buyer].poolWeight
        );

        require(
            amountsInAllocation[buyer].add(_amount) <= maxBuy,
            "Buying limit has been exceeded in Allocation round"
        );

        amountsInAllocation[buyer] = amountsInAllocation[buyer].add(_amount);
        capacity = capacity.add(_amount);
        capacityAllocation = capacityAllocation.add(_amount);
        // safe transfer payIntoken to launchpad
        launchpadData.payInToken.transferFrom(buyer, address(this), _amount);

        emit BuyTokenInAllocationRound(buyer, _amount);
    }

    /**
     * Buy token for first round
     */
    function buyTokenFCFS(uint256 _amount) external checkWhoCanBuy {
        require(_amount > 0, "Amount must the greater than 0");
        require(status != Statuses.CANCELLED, "Launchpad is cancelled");
        require(status != Statuses.FINZALIZE, "Launchpad is finalized");
        // // check start, end time
        // require(
        //     block.timestamp > launchpadData.startAt,
        //     "Launchpad do not start yet"
        // );

        // check time FCFS

        require(
            block.timestamp > launchpadData.fcfs.startAt,
            "FCFS round dont start yet"
        );
        require(
            block.timestamp < launchpadData.fcfs.endAt,
            "FCFS round expired"
        );

        address buyer = _msgSender();

        // Just buy max 25% from Alloaction round
        uint256 percentInDecimals = 100 * DECIMALS_PERCENT;
        uint256 maxBuy = launchpadData
            .baseAllocation
            .mul(registrationList[buyer].poolWeight)
            .mul(percentCanBuyInFCFS)
            .div(percentInDecimals);

        require(
            amountsInFCFS[buyer].add(_amount) <= maxBuy,
            "Buying limit has been exceeded in FCFS round"
        );

        amountsInFCFS[buyer] = amountsInFCFS[buyer].add(_amount);
        capacity = capacity.add(_amount);
        capacityFCFS = capacityFCFS.add(_amount);

        // safe transfer payIntoken to launchpad
        launchpadData.payInToken.transferFrom(buyer, address(this), _amount);

        emit BuyTokenInAllocationFCFS(buyer, _amount);
    }

    /**
     * Claim
     */
    function claim(uint8 _index)
        external
        returns (uint256 amount, uint256 claimAt)
    {
        require(status == Statuses.FINZALIZE, "Launchpad do not finalized yet");
        address buyer = _msgSender();
        uint256 amountUserStaked = amountsInAllocation[buyer].add(
            amountsInFCFS[buyer]
        );
        require(amountUserStaked > 0, "Wallet do not contribute token yet");
        require(_index < vestingTimeline.percents.length, "Index invalid");
        require(_isUserClaimed(buyer, _index), "Address claimed");

        // check user vested

        // check it's time to claim with _index vesting timeline
        uint256 percent = vestingTimeline.percents[_index];
        uint256 timestamp = vestingTimeline.timestamps[_index];

        require(block.timestamp > timestamp, "It is not time to next claim");

        uint256 decimalsOfToken = launchpadData.payInToken.decimals();
        uint256 amountOfUser = amountUserStaked
            .mul(launchpadData.presaleRate)
            .div(10**decimalsOfToken);

        uint256 percentInDecimals = 100 * DECIMALS_PERCENT;

        uint256 amountWillVesting = amountOfUser.mul(percent).div(percentInDecimals);

        // safe transfer token's launchpad for user
        launchpadData.token.transfer(buyer, amountWillVesting);

        // store vesting history
        VestingHistory memory history = VestingHistory(
            _index,
            amountWillVesting,
            block.timestamp
        );
        vestingHistories[buyer].push(history);

        emit ClaimToken(buyer, amountWillVesting);
        return (amountWillVesting, timestamp);
    }

    /**
     * Emergency Withdraw
     */
    function emergencyWithdraw() external {
        require(status != Statuses.FINZALIZE, "Launchpad is finalized");

        address buyer = _msgSender();

        uint256 amountUserStaked = amountsInAllocation[buyer].add(
            amountsInFCFS[buyer]
        );

        uint256 percentInDecimals = 100 * DECIMALS_PERCENT;

        uint256 amountFinal = amountUserStaked
            .mul(percentInDecimals.sub(emergencyWithdrawFee))
            .div(percentInDecimals);

        capacityAllocation = capacityAllocation.sub(amountsInAllocation[buyer]);
        capacityFCFS = capacityFCFS.sub(amountsInFCFS[buyer]);
        amountsInAllocation[buyer] = 0;
        amountsInFCFS[buyer] = 0;

        capacity = capacity.sub(amountUserStaked);

        launchpadData.payInToken.transfer(buyer, amountFinal);

        emit EmergencyWithdraw(buyer, amountFinal);
    }

    /**
     * Withdraw token staked when launchpad canncelled
     */
    function withdrawToken() external {
        require(status == Statuses.CANCELLED, "Launchpad is not cancelled yet");

        address buyer = _msgSender();

        uint256 amountUserStaked = amountsInAllocation[buyer].add(
            amountsInFCFS[buyer]
        );

        capacityAllocation = capacityAllocation.sub(amountsInAllocation[buyer]);
        capacityFCFS = capacityFCFS.sub(amountsInFCFS[buyer]);
        amountsInAllocation[buyer] = 0;
        amountsInFCFS[buyer] = 0;
        capacity = capacity.sub(amountUserStaked);

        launchpadData.payInToken.transfer(buyer, amountUserStaked);

        emit WithdrawToken(buyer, amountUserStaked);
    }

    /******************************************* Common function below *******************************************/
    /**
     * @dev Amount of address
     */
    function amountStaked(address _addr) public view returns (uint256) {
        return amountsInAllocation[_addr].add(amountsInFCFS[_addr]);
    }

    function getMaxTokenPayment(address _addr) public view returns (uint256) {
        // BUSD
        uint256 maxBuy = launchpadData.baseAllocation.mul(
            registrationList[_addr].poolWeight
        );
        return maxBuy;
    }

    function getLaunchpadData() public view returns (LaunchpadData memory) {
        return launchpadData;
    }

    function getLaunchpadVesting()
        public
        view
        returns (VestingTimeline memory)
    {
        return vestingTimeline;
    }

    function getVestingHistories(address _addr)
        public
        view
        returns (VestingHistory[] memory)
    {
        return vestingHistories[_addr];
    }

    /******************************************* Internal function below *******************************************/
    function _isUserClaimed(address _addr, uint8 _index)
        internal
        view
        returns (bool)
    {
        VestingHistory[] memory histories = vestingHistories[_addr];
        for (uint8 i = 0; i < histories.length; i++) {
            if (histories[i].index == _index) return false;
        }
        return true;
    }

    function _handleUnsoldToken() internal {
        uint256 remainCap = launchpadData.hardCap.sub(capacity);
        uint256 decimalsOfToken = launchpadData.payInToken.decimals();
        uint256 remainToken = remainCap.mul(launchpadData.presaleRate).div(
            10**decimalsOfToken
        );
        if (launchpadData.unsoldToken == SharedConstants.UnsoldToken.REFUND) {
            launchpadData.token.transfer(owner(), remainToken);
        }

        if (launchpadData.unsoldToken == SharedConstants.UnsoldToken.BURN) {
            launchpadData.token.transfer(BURN_ADDRESS, remainToken);
        }
    }
}
