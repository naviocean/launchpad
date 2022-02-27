// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/erc20/IERC20.sol";
import "@openzeppelin/contracts/token/erc20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./../interfaces/IBHOStaking.sol";
import "./../libs/SharedConstants.sol";
import "./../../interfaces/IERC20Extented.sol";
import "./BHOLaunchpad.sol";

contract BHOLaunchpadFactory is OwnableUpgradeable, SharedConstants {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public SERVICE_COST = 0;
    IBHOStaking public staking;

    /* events */
    event NewBHOLaunchpad(address indexed launchpadAddr);

    /* Modifier */

    function initialize(IBHOStaking _staking) public initializer {
        staking = _staking;
        __Ownable_init();
    }

    /**
     *  create launchpad
     */
    function createLaunchpad(
        LaunchpadData memory _launchpadData,
        VestingTimeline memory _vestingTimeline,
        address _ownerAddr
    ) external onlyOwner returns (address) {
        BHOLaunchpad launchpad = new BHOLaunchpad(
            _launchpadData,
            _vestingTimeline,
            staking,
            _ownerAddr
        );

        emit NewBHOLaunchpad(address(launchpad));
        _transferTokenSupply(
            _launchpadData.token,
            _launchpadData.presaleRate,
            _launchpadData.hardCap,
            address(launchpad)
        );
        return address(launchpad);
    }

    /**
     * @dev collect BNB
     */
    function collectBNB() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev collect Token from contract
     */
    function collectToken(IERC20 _token) public onlyOwner {
        _token.transfer(owner(), _token.balanceOf(address(this)));
    }

    /**
     * @dev collect BNB
     */
    function setServiceCost(uint256 _newSerCost) public {
        SERVICE_COST = _newSerCost;
    }

    /******************************************* Internal function below *******************************************/
    function _transferTokenSupply(
        IERC20Extented _token,
        uint256 _presaleRate,
        uint256 _hardCap,
        address _launchpadAddr
    ) internal {
        uint256 tokenAmount = _presaleRate.mul(_hardCap).div(
            10**_token.decimals()
        );
        _token.transferFrom(_msgSender(), _launchpadAddr, tokenAmount);
    }
}
