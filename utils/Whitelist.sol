
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Whitelist is Ownable {
    mapping(address => bool) private whitelist;
    // event AddedToWhitelist(address indexed account);
    event AddedMultiToWhitelist(address[] indexed accounts);
    // event RemovedFromWhitelist(address indexed account);
    event RemovedMultiFromWhitelist(address[] indexed account);

    modifier onlyWhitelisted() {
        require(isWhitelisted(msg.sender), "Whitelist: address does not exist");
        _;
    }

    // function add(address _address) public onlyOwner {
    //     whitelist[_address] = true;
    //     emit AddedToWhitelist(_address);
    // }

    function addMulti(address[] memory _addresses) public onlyOwner {
        for (uint i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = true;
        }
        emit AddedMultiToWhitelist(_addresses);
    }

    // function remove(address _address) public onlyOwner {
    //     whitelist[_address] = false;
    //     emit RemovedFromWhitelist(_address);
    // }

    function removeMulti(address[] memory _addresses) public onlyOwner {
        for (uint i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = false;
        }
        emit RemovedMultiFromWhitelist(_addresses);
    }

    function isWhitelisted(address _address) public view returns (bool) {
        return whitelist[_address];
    }
}
