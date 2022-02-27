// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IBHOStaking {
    function levelOf(address _addr)
        external
        view
        returns (
            string memory id,
            uint256 minAmount,
            uint256 poolWeight
        );
}
