// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

library SafeArrayUint {

    function sum(
        uint256[] memory arr
    ) internal pure returns (uint256) {
        uint i;
        uint256 s = 0;   
        for(i = 0; i < arr.length; i++)
          s = s + arr[i];
        return s;
    }
}
