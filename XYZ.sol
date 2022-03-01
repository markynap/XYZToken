//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Router02.sol";
import "./SafeMath.sol";

contract Sender {

    address public XYZ;

    constructor(address XYZ_) {
        XYZ = XYZ_;
    }

    function send(address to) external {
        require(msg.sender == XYZ, 'Only XYZ');
        IERC20(XYZ).transfer(to, IERC20(XYZ).balanceOf(address(this)));
    }

}

contract XYZToken is IERC20, Ownable {

    using SafeMath for uint256;

    // total supply
    uint256 private _totalSupply;

    // token data
    string constant _name = "XYZToken";
    string constant _symbol = "XYZ";
    uint8 constant _decimals = 18;
    
    // balances
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    // PCS Router
    IUniswapV2Router02 router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address[] path;

    // Taxation on transfers
    uint256 public reducedBuyFee      = 50;
    uint256 public buyFee             = 70;
    uint256 public sellFee            = 70;
    uint256 public transferFee        = 45;
    uint256 public constant TAX_DENOM = 1000;

    // reduced buyer sender, cause Uniswap can't send tokens back to address
    Sender public sender;

    // permissions
    struct Permissions {
        bool isFeeExempt;
        bool rewardsExempt;
        bool isLiquidityPool;
    }
    mapping ( address => Permissions ) permissions;

    // Fee Recipients
    address public sellFeeRecipient;
    address public buyFeeRecipient;
    address public transferFeeRecipient;

    // events
    event SetBuyFeeRecipient(address recipient);
    event SetSellFeeRecipient(address recipient);
    event SetTransferFeeRecipient(address recipient);
    event DistributorUpgraded(address newDistributor);
    event SetRewardsExempt(address account, bool isExempt);
    event SetFeeExemption(address account, bool isFeeExempt);
    event SetAutomatedMarketMaker(address account, bool isMarketMaker);
    event SetFees(uint256 reducedBuyFee, uint256 buyFee, uint256 sellFee, uint256 transferFee);
    
    // modifiers
    modifier onlyOwner(){
        require(msg.sender == owner, 'Only Owner');
        _;
    }

    constructor(address distributor) {
        
        // initialize sender
        sender = new Sender(address(this));

        // set initial starting supply
        _totalSupply = 10**9 * 10**_decimals;

        // swapper info
        path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(this);

        // Set initial automated market maker
        permissions[
            IUniswapV2Factory(router.factory()).createPair(router.WETH(), address(this))
        ].isLiquidityPool = true;

        // initial supply allocation
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    
    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
  
    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, 'Insufficient Allowance');
        return _transferFrom(sender, recipient, amount);
    }

    function burn(uint256 amount) external returns (bool) {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external returns (bool) {
        _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, 'Insufficient Allowance');
        _burn(account, amount);
    }
    
    /** Internal Transfer */
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(
            recipient != address(0),
            'Zero Recipient'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= balanceOf(sender),
            'Insufficient Balance'
        );
        
        // decrement sender balance
        _balances[sender] = _balances[sender].sub(amount, 'Balance Underflow');
        // fee for transaction
        (uint256 fee, address feeDestination) = getTax(sender, recipient, amount);

        // allocate fee
        if (fee > 0 && feeDestination != address(0)) {
            _balances[feeDestination] = _balances[feeDestination].add(fee);
            emit Transfer(sender, feeDestination, fee);
        }

        // give amount to recipient
        uint256 sendAmount = amount.sub(fee);
        _balances[recipient] = _balances[recipient].add(sendAmount);

        // emit transfer
        emit Transfer(sender, recipient, sendAmount);
    }

    function withdraw(address token) external onlyOwner {
        IERC20(token).transfer(owner, IERC20(token).balanceOf(address(this)));
    }

    function withdrawBNB() external onlyOwner {
        _sendBNB(owner, address(this).balance);
    }

    function setTransferFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        transferFeeRecipient = recipient;
        emit SetTransferFeeRecipient(recipient);
    }

    function setBuyFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        buyFeeRecipient = recipient;
        emit SetBuyFeeRecipient(recipient);
    }

    function setSellFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero Address');
        sellFeeRecipient = recipient;
        emit SetSellFeeRecipient(recipient);
    }

    function registerAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(!permissions[account].isLiquidityPool, 'Already An AMM');
        permissions[account].isLiquidityPool = true;
        emit SetAutomatedMarketMaker(account, true);
    }

    function unRegisterAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(permissions[account].isLiquidityPool, 'Not An AMM');
        permissions[account].isLiquidityPool = false;
        emit SetAutomatedMarketMaker(account, false);
    }

    function setFees(uint _reducedBuyFee, uint _buyFee, uint _sellFee, uint _transferFee) external onlyOwner {
        require(
            buyFee <= TAX_DENOM.div(8),
            'Buy Fee Too High'
        );
        require(
            buyFee <= TAX_DENOM.div(8),
            'Sell Fee Too High'
        );
        require(
            buyFee <= TAX_DENOM.div(8),
            'Transfer Fee Too High'
        );
        require(
            reducedBuyFee <= TAX_DENOM.div(8),
            'Reduced Buy Fee Too High'
        );

        buyFee = _buyFee;
        sellFee = _sellFee;
        transferFee = _transferFee;
        reducedBuyFee = _reducedBuyFee;

        emit SetFees(_reducedBuyFee, _buyFee, _sellFee, _transferFee);
    }

    function setFeeExempt(address account, bool isExempt) external onlyOwner {
        require(account != address(0), 'Zero Address');

        permissions[account].isFeeExempt = isExempt;
        emit SetFeeExemption(account, isExempt);
    }

    receive() external payable {
        require(msg.value > 100);

        // calculate fee for reduced buy
        uint256 fee = isFeeExempt[msg.sender] ? 0 : msg.value.mul(reducedBuyFee).div(TAX_DENOM);

        // send bnb to buy fee recipient
        if (fee > 0) {
            _sendBNB(buyFeeRecipient, fee);
        }

        // use rest of bnb to buy token for sender
        uint256 amount = msg.value.sub(fee);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(0, path, address(sender), block.timestamp + 300);

        // allocate tokens to sender
        sender.send(msg.sender);
    }

    function getTax(address sender, address recipient, uint256 amount) public view returns (uint256, address) {
        if ( permissions[sender].isFeeExempt || permissions[recipient].isFeeExempt ) {
            return (0, address(0));
        }
        return permissions[sender].isLiquidityPool ? 
               (amount.mul(buyFee).div(TAX_DENOM), buyFeeRecipient) : 
               permissions[recipient].isLiquidityPool ? 
               (amount.mul(sellFee).div(TAX_DENOM), sellFeeRecipient) :
               (amount.mul(transferFee).div(TAX_DENOM), transferFeeRecipient);
    }

    function _sendBNB(address recipient, uint256 amount) internal {
        (bool s,) = payable(recipient).call{value: amount}("");
        require(s);
    }

    function _burn(address account, uint256 amount) internal returns (bool) {
        require(
            account != address(0),
            'Zero Address'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        _balances[account] = _balances[sender].sub(amount, 'Balance Underflow');
        _totalSupply = _totalSupply.sub(amount, 'Supply Underflow');
    }
}