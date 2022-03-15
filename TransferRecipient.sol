//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Router02.sol";

interface IReceiver {
    function deposit(uint256 amount) external;
}
interface IBurnable {
    function burn(uint256 amount) external;
}
contract FeeReceiver is Ownable {

    // XYZ Token
    IERC20 public token;

    // Type of Receiver
    string public Type;

    // Fund Fees
    uint public burnFee         = 67;
    uint public liquidityFee    = 33;

    // Fee Recipients
    address public liquidityFarm;

    // Dev Royalty
    address constant dev = 0x9B74E1E946B2eB3c50FAf6267ac78B953DA70FAf;

    // events
    event UpdatedFees(uint burnFee, uint liquidityFee);
    event UpdatedLiquidityFarm(address newFarm);

    /**
        Type As In BuyReceiver, SellReceiver, TransferReceiver - for tracking
     */
    constructor(string memory _Type){
        Type = _Type;
    }

    function trigger() external {

        // split up amounts
        uint lAmt = ( token.balanceOf(address(this)) * liquidityFee ) / feeDenom();

        // deposit into liquidity farm
        token.approve(liquidityFarm, lAmt);
        IReceiver(liquidityFarm).deposit(lAmt);

        // burn remaining tokens
        if (token.balanceOf(address(this)) > 0) {
            token.transfer(dev, token.balanceOf(address(this)) / 10);
            IBurnable(address(token)).burn(token.balanceOf(address(this)));
        }
    }

    function updateLiquidityFarm(address farm) external onlyOwner {
        require(farm != address(0));
        liquidityFarm = farm;
        emit UpdatedLiquidityFarm(farm);
    }

    function updateFees(uint nBurnFee, uint nLiquidityFee) external onlyOwner {
        burnFee = nBurnFee;
        liquidityFee = nLiquidityFee;
        emit UpdatedFees(nBurnFee, nLiquidityFee);
    }

    function pairToken(address _token) external onlyOwner {
        require(address(token) == address(0) && _token != address(0), 'Already Paired');
        token = IERC20(_token);
        path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();
    }

    function withdraw() external onlyOwner {
        (bool s,) = payable(owner).call{value: address(this).balance}("");
        require(s);
    }

    function withdrawTokens() external onlyOwner {
        token.transfer(owner, token.balanceOf(address(this)));
    }

    function feeDenom() public view returns (uint256) {
        return liquidityFee + interestFundFee + burnFee;
    }

    receive() external payable {}
}