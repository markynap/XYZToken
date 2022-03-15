//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Router02.sol";

interface IReceiver {
    function deposit(uint256 amount) external;
}
contract FeeReceiver is Ownable {

    // XYZ Token
    IERC20 public token;

    // Type of Receiver
    string public Type;

    // PCS Router
    IUniswapV2Router02 router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // Fund Fees
    uint public interestFundFee = 90;
    uint public liquidityFee    = 10;

    // Fee Recipients
    address public interestFund;
    address public liquidityFarm;

    // Dev Royalty
    address constant dev = 0x9B74E1E946B2eB3c50FAf6267ac78B953DA70FAf;

    // Token -> BNB
    address[] path;

    // events
    event UpdatedFees(uint interestFee, uint liquidityFee);
    event UpdatedInterestFund(address newFund);
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

        // swap tokens for BNB
        token.approve(address(router), token.balanceOf(address(this)));
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(token.balanceOf(address(this)), 0, path, address(this), block.timestamp + 300);
        
        // deliver BNB to interest fund contract
        if (address(this).balance > 0) {
            (bool s,) = payable(dev).call{value: ( address(this).balance * 20 ) / 100}("");
            require(s, 'Dev transfer failure');

            (bool s2,) = payable(interestFund).call{value: address(this).balance}("");
            require(s2, 'Interest Fund failure');
        }
    }

    function updateLiquidityFarm(address farm) external onlyOwner {
        require(farm != address(0));
        liquidityFarm = farm;
        emit UpdatedLiquidityFarm(farm);
    }

    function updateInterestFund(address fund) external onlyOwner {
        require(fund != address(0));
        interestFund = fund;
        emit UpdatedInterestFund(fund);
    }

    function updateFees(uint nInterestFee, uint nLiquidityFee) external onlyOwner {
        interestFundFee = nInterestFee;
        liquidityFee = nLiquidityFee;
        emit UpdatedFees(nInterestFee, nLiquidityFee);
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
        return liquidityFee + interestFundFee;
    }

    receive() external payable {}
}