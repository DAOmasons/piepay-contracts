// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// NO IMPORTS NEEDED - this is just an interface

interface ISplitMain {
    function createSplit(
        address[] calldata accounts,
        uint32[] calldata percentAllocations,
        uint32 distributorFee,
        address controller
    ) external returns (address);
    
    function distributeERC20(
        address split,
        address token,
        address[] calldata accounts,
        uint32[] calldata percentAllocations,
        uint32 distributorFee,
        address distributorAddress
    ) external;
    
    function distributeETH(
        address split,
        address[] calldata accounts,
        uint32[] calldata percentAllocations,
        uint32 distributorFee,
        address distributorAddress
    ) external;
    
    function withdraw(
        address account,
        uint256 withdrawETH,
        address[] calldata tokens
    ) external;
    
    function getETHBalance(address account) external view returns (uint256);
    
    function getERC20Balance(address account, address token) external view returns (uint256);
}