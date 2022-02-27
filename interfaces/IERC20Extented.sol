import "@openzeppelin/contracts/token/erc20/IERC20.sol";
pragma solidity ^0.8.10;

interface IERC20Extented is IERC20 {
    function decimals() external view returns (uint8);
}