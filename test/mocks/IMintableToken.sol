// Simple interface for the mint function (since it's not in standard IERC20)
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMintableToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function decimals() external view returns (uint8);
}