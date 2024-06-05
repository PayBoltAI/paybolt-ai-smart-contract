// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

library Address {
    function sendValue(address payable recipient, uint256 amount) internal returns(bool){
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        return success; // always proceeds
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            unchecked {
                _approve(sender, _msgSender(), currentAllowance - amount);
            }
        }

        _transfer(sender, recipient, amount);

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mintOnce(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract PayBoltAI is ERC20, Ownable {
    using Address for address payable;
    
    event FeeRecipientChanged(address account); 
    event FeePointsOnBuyChanged(uint newFeePoints); 
    event FeePointsOnSellChanged(uint newFeePoints); 
    event FeePointsOnReflectionChanged(uint newFeePoints); 
    event MinimumTokensBeforeSwapChanged(uint newMinimum); 
    event ExemptFee(address account);
    event RevokeFeeExemption(address account);

    bool private _swapping;
    mapping (address => bool) private _feeExemption;

    IRouter public router;
    address public pair;
    uint public maxTotalFeePointsAllowed; 
    uint public feePointsOnBuy; 
    uint public feePointsOnSell; 
    uint public feePointsOnReflection; 
    uint public totalFeePoints; 
    uint public minimumTokensBeforeSwap; 

    address public feeRecipient;
    address public reflectionFeeRecipient;

    constructor ()
        ERC20("PayBolt AI", "PAYAI") 
        Ownable()
    {
        maxTotalFeePointsAllowed = 1_000;
        totalFeePoints = 1_000;
        feePointsOnBuy = 300; 
        feePointsOnSell = 700; 
        feePointsOnReflection = 140;
        minimumTokensBeforeSwap = 250_000 * 10**decimals();

        feeRecipient = 0xd65e6E66adDBD06c313c9C9024f42565D2B66dF5; 
        reflectionFeeRecipient = 0x2e48771C9316a1361100737B861d20aF65433a18; 

        IRouter _router = IRouter(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24);
        address _pair = IFactory(_router.factory()).createPair(address(this), _router.WETH());
        router = _router;
        pair = _pair;

        _approve(address(this), address(router), type(uint).max);

        exemptFee(msg.sender);

        _mintOnce(msg.sender, 10_000_000_000 * 10**decimals());
    }

    receive() external payable {}

    function rescueStuckFund() public onlyOwner {
        payable(owner()).sendValue(address(this).balance);
    }

    function updateFeeRecipient(address newRecipient) public onlyOwner {
        require(newRecipient != address(0), "Fee receiver cannot be the zero address");
        feeRecipient = newRecipient;
        emit FeeRecipientChanged(_msgSender());
    }

    function updateReflectionFeeRecipient(address newRecipient) public onlyOwner {
        require(newRecipient != address(0), "Fee receiver cannot be the zero address");
        reflectionFeeRecipient = newRecipient;
        emit FeeRecipientChanged(_msgSender());
    }

    function updateFeePointsOnBuy(uint newFeePointsOnBuy) public onlyOwner {
        require((newFeePointsOnBuy + feePointsOnSell) <= maxTotalFeePointsAllowed, "Exceed max allowed fee points");
        feePointsOnBuy = newFeePointsOnBuy;
        totalFeePoints = feePointsOnBuy + feePointsOnSell; 
        emit FeePointsOnBuyChanged(newFeePointsOnBuy);
    }

    function updateFeePointsOnSell(uint newFeePointsOnSell) public onlyOwner {
        require((feePointsOnBuy + newFeePointsOnSell) <= maxTotalFeePointsAllowed, "Exceed max allowed fee points");
        feePointsOnSell = newFeePointsOnSell;
        totalFeePoints = feePointsOnBuy + feePointsOnSell; 
        emit FeePointsOnSellChanged(newFeePointsOnSell);
    }

    function updateFeePointsOnReflection(uint newFeePointsOnReflection) public onlyOwner {
        require(newFeePointsOnReflection <= maxTotalFeePointsAllowed, "Exceed max allowed fee points");
        feePointsOnReflection = newFeePointsOnReflection;
        emit FeePointsOnReflectionChanged(newFeePointsOnReflection);
    }

    function updateMinimumTokensBeforeSwap(uint newMinimumTokensBeforeSwap) public onlyOwner {
        require(newMinimumTokensBeforeSwap >= (1_000 * 10**decimals()), "New minimumTokensBeforeSwap must be at least 1,000 * 10**18");
        minimumTokensBeforeSwap = newMinimumTokensBeforeSwap;
        emit MinimumTokensBeforeSwapChanged(newMinimumTokensBeforeSwap);
    }

    function exemptFee(address account) public onlyOwner {
        require(!_feeExemption[account], "Account is already exempted");
        _feeExemption[account] = true;
        emit ExemptFee(account);
    }

    function revokeFeeExemption(address account) public onlyOwner {
        require(_feeExemption[account], "Account is not exempted");
        _feeExemption[account] = false;
        emit RevokeFeeExemption(account);
    }

    function isFeeExempted(address account) public view returns (bool) { 
        return _feeExemption[account];
    }

    function _transfer(address from, address to, uint amount) internal override {
        if (_swapping || amount == 0 || isFeeExempted(from) || isFeeExempted(to) || (from != pair && to != pair)) {
            super._transfer(from, to, amount);
        } else {
            uint _feePoints; 
            if (from == pair) {
                _feePoints = feePointsOnBuy;
            } else {
                _feePoints = feePointsOnSell;
            }

            if (_feePoints > 0) {
                uint fees = amount * _feePoints / 10_000;
                amount = amount - fees;

                super._transfer(from, address(this), fees);
            }

            uint contractTokenBalance = balanceOf(address(this));
            if (
                from != pair && 
                contractTokenBalance >= minimumTokensBeforeSwap && 
                !_swapping
            ) {
                _swapping = true; 
                swapTokensForEth(contractTokenBalance);
                _swapping = false; 
            }
                
            super._transfer(from, to, amount);
        }
    }

    function swapTokensForEth(uint tokenAmount) private {
        uint256 initialBalance = address(this).balance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        
        try router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        ) {} catch {
            return;
        }

        uint256 deltaBalance = address(this).balance - initialBalance;

        if (feePointsOnReflection > 0) {
            uint256 reflectionBalance = deltaBalance * feePointsOnReflection / totalFeePoints;
            uint256 remainingBalance = deltaBalance - reflectionBalance;
            
            if (remainingBalance > 0) {
                payable(feeRecipient).sendValue(remainingBalance);
            }

            payable(reflectionFeeRecipient).sendValue(reflectionBalance);
        } else {
            payable(feeRecipient).sendValue(deltaBalance);
        }
    }
}