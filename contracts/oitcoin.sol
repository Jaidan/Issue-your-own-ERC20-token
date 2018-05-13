pragma solidity ^0.4.22;

// ----------------------------------------------------------------------------
// 'OIT Mining' token contract
//
// Deployed to : 
// Symbol      : OIT-M
// Name        : OIT Mining Token
// Decimals    : 18
//
// 
// TODO: 
// 1. Add state machine to enable turning on/off
// Based on https://github.com/bitfwdcommunity/Issue-your-own-ERC20-token
// (c) by Moritz Neto with BokkyPooBah / Bok Consulting Pty Ltd Au 2017. The MIT Licence.
//
// ----------------------------------------------------------------------------


// ----------------------------------------------------------------------------
// Safe maths
// ----------------------------------------------------------------------------
library SafeMath {
    function add(uint256 a, uint256 b) public pure returns (uint256 c) {
        c = a + b;
        require(c >= a);
    }
    function sub(uint256 a, uint256 b) public pure returns (uint256 c) {
        require(b <= a);
        c = a - b;
    }
    function mul(uint256 a, uint256 b) public pure returns (uint256 c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }
    function div(uint256 a, uint256 b) public pure returns (uint256 c) {
        require(b > 0);
        c = a / b;
    }
}


// ----------------------------------------------------------------------------
// ERC Token Standard #20 Interface
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
// ----------------------------------------------------------------------------
contract ERC20 {
    function totalSupply() public view returns (uint);
    function balanceOf(address tokenOwner) public view returns (uint balance);
    function allowance(address tokenOwner, address spender) public view returns (uint remaining);
    function transfer(address to, uint tokens) public returns (bool success);
    function approve(address spender, uint tokens) public returns (bool success);
    function transferFrom(address from, address to, uint tokens) public returns (bool success);

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}


contract OITToken is ERC20 {
    using SafeMath for uint256;

    struct Account {
        uint256 balance;
        uint256 dividendsPaid;
        uint256 lastDividendPoints;
    }

    uint constant pointMultiplier = 10e18;
    string public constant symbol = "OIT-M";
    string public constant name = "OIT Mining Token";
    uint8 public constant decimals = 18;
    uint256 private _totalSupply = 0;
    uint256 public unclaimedDividends = 0;
    uint256 public totalDividendPoints = 0;
    address public controller;
    mapping(address => Account) accounts;
    mapping(address => mapping(address => uint)) allowed;
    event DividendPaid(address indexed account, uint256 amount);


    modifier controllerOnly {
        require(msg.sender == controller);
        _;
    }

    function mint(address _recipient, uint256 _value) external controllerOnly {
        require(_value > 0);
        Account storage recipient = accounts[_recipient];
        recipient.balance.add(_value);
        _totalSupply = _totalSupply.add(_value);
        emit Transfer(0x0, _recipient, _value);
    }

    function dividendsOwing(Account account) internal view returns(uint256) {
        uint256 newDividendPoints = totalDividendPoints - account.lastDividendPoints;
        return (account.balance * newDividendPoints) / pointMultiplier;
    }

    function balanceOf(address tokenOwner) public view returns (uint256 balance) {
        return accounts[tokenOwner].balance;
    }

    /**
    *   @dev Allows another account/contract to spend some tokens on its behalf
    *   throws on any error rather then return a false flag to minimize user errors
    *
    *   also, to minimize the risk of the approve/transferFrom attack vector
    *   approve has to be called twice in 2 separate transactions - once to
    *   change the allowance to 0 and secondly to change it to the new allowance
    *   value
    *
    *   @param _spender      approved address
    *   @param _amount       allowance amount
    *
    *   @return true if the approval was successful
    */
    function approve(address _spender, uint _amount) public returns (bool success) {
        require((_amount == 0) || (allowed[msg.sender][_spender] == 0));
        allowed[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;

    }

   /**
    *   @dev Function to check the amount of tokens that an owner allowed to a spender.
    *
    *   @param _owner        the address which owns the funds
    *   @param _spender      the address which will spend the funds
    *
    *   @return              the amount of tokens still avaible for the spender
    */
    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowed[_owner][_spender];
    }

    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool) {
        Account storage from = accounts[_from];
        Account storage recipient = accounts[_to];
        from.balance = from.balance.sub(_amount);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amount);
        recipient.balance = recipient.balance.add(_amount);
        emit Transfer(_from, _to, _amount);
        return true;
    }
    
    function totalSupply() public view returns(uint256) {
        return _totalSupply;
    }

   /**
    *   @dev Send tokens 
    *    throws on any error rather then return a false flag to minimize
    *   user errors
    *   @param _to           target address
    *   @param _amount       transfer amount
    *
    *   @return true if the transfer was successful
    */
    function transfer(address _to, uint256 _amount) public returns (bool success) {
        Account storage sender = accounts[msg.sender];
        Account storage recipient = accounts[_to];
        sender.balance = sender.balance.sub(_amount);
        recipient.balance = recipient.balance.add(_amount);
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function payDividends(address _account) external controllerOnly {
        Account storage account = accounts[_account];
        uint256 owing = dividendsOwing(account);
        if (owing > 0) {
            unclaimedDividends = unclaimedDividends.sub(owing);
            _account.transfer(owing);
            account.lastDividendPoints = totalDividendPoints;
            emit DividendPaid(_account, owing);
        }
    }
    
    function() external payable {
        uint256 newPoints = msg.value.mul(pointMultiplier).div(_totalSupply);
        totalDividendPoints = totalDividendPoints.add(newPoints);
    }
}


contract Owned {
    address public owner;
    address public newOwner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }

    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}


contract OITMining is Owned {
    OITToken public OIT = OITToken(this);
    using SafeMath for uint256;
    uint256 public ethRate = 730;
    uint256 dollarsPerToken = 10;
    uint256 tokenPrice;

    enum Status {
        Created,
        InitialInvestment,
        OpenInvestment,
        Closed,
        Paused
    }

    Status status = Status.Created;

    event Disbursement(uint256 amount);
    event LogStartInitialInvestment();
    event LogStartOpenInvestment();
    event LogCloseInvestment();
    event LogPauseAll();

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    constructor() public {
        updatePrice();
    }

    modifier requireActive {
        require((status == Status.InitialInvestment) || (status == Status.OpenInvestment) || (status == Status.Closed));
        _;
    }
    
    modifier investmentActive {
        require((status == Status.InitialInvestment) || (status == Status.OpenInvestment));
        _;
    }


    function invest(address _investor, uint256 _value) private {
        OIT.mint(_investor, _value);
    }

    function setRate(uint256 _ethRate) external onlyOwner {
        ethRate = _ethRate;
        updatePrice();
    }

    function updatePrice() internal {
        tokenPrice = dollarsPerToken.div(ethRate);
    }

    function disburse(uint256 _amount) external onlyOwner requireActive {
        address(OIT).transfer(_amount);
        emit Disbursement(_amount);
    }

    function offlineInvest(address _investor, uint256 _value) external onlyOwner investmentActive {
        invest(_investor, _value);
    }

    function withdrawDividends() external requireActive {
        OIT.payDividends(msg.sender);
    }

    function startInitialInvestment() external onlyOwner {
        require(status == Status.Created);
        status = Status.InitialInvestment;
        emit LogStartInitialInvestment();
    }

    function startOpenInvestment() external onlyOwner {
        require((status == Status.Created) || (status == Status.Closed) || (status == Status.Paused));
        status = Status.InitialInvestment;
        emit LogStartOpenInvestment();
    }

    function stopInvestment() external onlyOwner requireActive {
        require((status == Status.InitialInvestment) || (status == Status.OpenInvestment) || (status == Status.Paused));
        status = Status.InitialInvestment;
        emit LogCloseInvestment();
    }

    function pauseAll() external onlyOwner {
        status = Status.Paused;
        emit LogPauseAll();
    }

    function() external payable {
        require(status == Status.OpenInvestment);
        OIT.mint(msg.sender, msg.value.div(tokenPrice));
    }
}
