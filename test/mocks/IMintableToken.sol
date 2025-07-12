// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMintableToken {
    function mint(address to, uint256 amount) external;
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}