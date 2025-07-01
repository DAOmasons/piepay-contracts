pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockDAI is ERC20 {
    constructor() ERC20("DAI Coin", "DAI") {
        // Mint initial supply to deployer
        _mint(msg.sender, 1000000 * 10**18); // 1M DAI (18 decimals)
    }
    
    function decimals() public pure override returns (uint8) {
        return 18; // DAI has 6 decimals
    }
    
    // Helper function for tests to mint tokens
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}