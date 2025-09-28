// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReputationSBT} from "./ReputationSBT.sol";

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address f, address t, uint256 v) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
    function allowance(address o, address s) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/* --------------------------- Ownable / Pausable --------------------------- */
abstract contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed prev, address indexed next);
    modifier onlyOwner() { require(msg.sender == owner, "NOT_OWNER"); _; }
    constructor() { owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    function transferOwnership(address next) external onlyOwner { 
        require(next != address(0), "ZERO_ADDR"); 
        emit OwnershipTransferred(owner, next); 
        owner = next; 
    }
}
abstract contract Pausable is Ownable {
    bool public paused;
    modifier whenNotPaused() { require(!paused, "PAUSED"); _; }
    function setPaused(bool p) external onlyOwner { paused = p; }
}
abstract contract ReentrancyGuard {
    uint256 private _g = 1;
    modifier nonReentrant() { require(_g == 1, "REENTRANCY"); _g = 2; _; _g = 1; }
}

/* ------------------------------ TrueMatchProtocol ------------------------------ */
contract TrueMatchProtocol is Pausable, ReentrancyGuard {
    IERC20 public immutable token;
    address public treasury;
    ReputationSBT public immutable sbt;

    uint256 public minStake = 1000e18;
    uint256 public slashPerValidReport = 50e18;
    uint256 public reportValidityThreshold = 3;
    uint256 public creditPrice = 1e18;
    uint256 public boostPrice = 20e18;
    uint256 public superlikePrice = 5e18;
    uint256 public referralReward = 25e18;
    uint256 public unstakeCooldown = 2 days;

    struct User {
        uint256 staked;
        uint256 stakeUnlockTime;
        uint256 credits;
        uint256 superlikes;
        uint256 boosts;
        uint256 reputation;
        uint256 reports;
        address referrer;
        bool claimedReferral;
    }
    mapping(address => User) public users;

    /* ---------------------------- Events ---------------------------- */
    event TreasuryChanged(address indexed t);
    event ParamsUpdated(uint256 minStake,uint256 slashPerValidReport,uint256 reportValidityThreshold,uint256 creditPrice,uint256 superlikePrice,uint256 boostPrice,uint256 referralReward);
    event Staked(address indexed user,uint256 amount);
    event UnstakeRequested(address indexed user,uint256 when);
    event Unstaked(address indexed user,uint256 amount);
    event CreditsPurchased(address indexed user,uint256 qty,uint256 paid);
    event SuperlikesPurchased(address indexed user,uint256 qty,uint256 paid);
    event BoostsPurchased(address indexed user,uint256 qty,uint256 paid);
    event CreditSpent(address indexed user,uint8 kind,uint256 remaining);
    event ReportFiled(address indexed reporter,address indexed target);
    event UserSlashed(address indexed target,uint256 amount,uint256 remainingStake);
    event ReputationUpdated(address indexed user,int256 delta,uint256 newScore,uint256 newTier);
    event ReferralLinked(address indexed referrer,address indexed referee);
    event ReferralRewardPaid(address indexed to,uint256 amount);

    constructor(address token_, address treasury_, address sbt_) {
        require(token_!=address(0) && treasury_!=address(0) && sbt_!=address(0),"ZERO_ADDR");
        token = IERC20(token_);
        treasury = treasury_;
        sbt = ReputationSBT(sbt_);
    }

    /* ---------------- Admin ---------------- */
    function setTreasury(address t) external onlyOwner {
        require(t!=address(0),"ZERO_ADDR");
        treasury = t;
        emit TreasuryChanged(t);
    }
    function setParams(uint256 _minStake,uint256 _slash,uint256 _thresh,uint256 _credit,uint256 _superlike,uint256 _boost,uint256 _refReward,uint256 _cooldown) external onlyOwner {
        minStake=_minStake; slashPerValidReport=_slash; reportValidityThreshold=_thresh;
        creditPrice=_credit; superlikePrice=_superlike; boostPrice=_boost; referralReward=_refReward;
        if(_cooldown>0)unstakeCooldown=_cooldown;
        emit ParamsUpdated(minStake,slashPerValidReport,reportValidityThreshold,creditPrice,superlikePrice,boostPrice,referralReward);
    }

    /* ---------------- Staking ---------------- */
    function stake(uint256 amount) external whenNotPaused nonReentrant {
        require(amount>0,"ZERO");
        users[msg.sender].staked+=amount;
        require(token.transferFrom(msg.sender,address(this),amount),"TRANSFER_FAIL");
        emit Staked(msg.sender,amount);
    }
    function requestUnstake() external whenNotPaused {
        User storage u=users[msg.sender];
        require(u.staked>0,"NO_STAKE");
        u.stakeUnlockTime=block.timestamp+unstakeCooldown;
        emit UnstakeRequested(msg.sender,u.stakeUnlockTime);
    }
    function unstake(uint256 amount) external whenNotPaused nonReentrant {
        User storage u=users[msg.sender];
        require(amount>0 && amount<=u.staked,"BAD_AMOUNT");
        require(u.stakeUnlockTime>0 && block.timestamp>=u.stakeUnlockTime,"LOCKED");
        u.staked-=amount;
        require(token.transfer(msg.sender,amount),"TRANSFER_FAIL");
        emit Unstaked(msg.sender,amount);
    }
    function hasPremium(address u) public view returns(bool){ return users[u].staked>=minStake; }

    /* ---------------- Credits ---------------- */
    function _pay(address from,uint256 amt) internal { require(token.transferFrom(from,treasury,amt),"PAY_FAIL"); }
    function buySwipeCredits(uint256 qty) external whenNotPaused nonReentrant {
        require(qty>0,"ZERO"); uint256 cost=qty*creditPrice; _pay(msg.sender,cost);
        users[msg.sender].credits+=qty; emit CreditsPurchased(msg.sender,qty,cost);
    }
    function buySuperlikes(uint256 qty) external whenNotPaused nonReentrant {
        require(qty>0,"ZERO"); uint256 cost=qty*superlikePrice; _pay(msg.sender,cost);
        users[msg.sender].superlikes+=qty; emit SuperlikesPurchased(msg.sender,qty,cost);
    }
    function buyBoosts(uint256 qty) external whenNotPaused nonReentrant {
        require(qty>0,"ZERO"); uint256 cost=qty*boostPrice; _pay(msg.sender,cost);
        users[msg.sender].boosts+=qty; emit BoostsPurchased(msg.sender,qty,cost);
    }

    function spendSwipe() external whenNotPaused {User storage u=users[msg.sender];require(u.credits>0,"NO_CREDITS");u.credits--;emit CreditSpent(msg.sender,0,u.credits);}
    function spendSuperlike() external whenNotPaused {User storage u=users[msg.sender];require(u.superlikes>0,"NO_SUPER");u.superlikes--;emit CreditSpent(msg.sender,1,u.superlikes);}
    function spendBoost() external whenNotPaused {User storage u=users[msg.sender];require(u.boosts>0,"NO_BOOST");u.boosts--;emit CreditSpent(msg.sender,2,u.boosts);}

    /* ---------------- Reports ---------------- */
    function reportUser(address target) external whenNotPaused {
        require(target!=address(0) && target!=msg.sender,"BAD_TARGET");
        users[target].reports++;
        emit ReportFiled(msg.sender,target);
        if(users[target].reports>=reportValidityThreshold && users[target].staked>0){
            uint256 slashAmt=slashPerValidReport>users[target].staked?users[target].staked:slashPerValidReport;
            users[target].staked-=slashAmt;
            require(token.transfer(treasury,slashAmt),"SLASH_FAIL");
            users[target].reports=0;
            emit UserSlashed(target,slashAmt,users[target].staked);
            _updateReputation(target,-10);
        }
    }

    /* ---------------- Reputation ---------------- */
    function updateReputation(address user,int256 delta) external onlyOwner { _updateReputation(user,delta); }
    function _updateReputation(address user,int256 delta) internal {
        User storage u=users[user];
        if(delta>=0){ u.reputation+=uint256(delta); }
        else{ uint256 d=uint256(-delta); u.reputation=d>=u.reputation?0:u.reputation-d; }
        uint256 tier=_tier(u.reputation);
        sbt.mintOrUpdate(user,tier);
        emit ReputationUpdated(user,delta,u.reputation,tier);
    }
    function _tier(uint256 score) internal pure returns(uint256){
        if(score>=200) return 3; if(score>=100) return 2; if(score>=25) return 1; return 0;
    }

    /* ---------------- Referrals ---------------- */
    function linkReferral(address referrer) external whenNotPaused nonReentrant {
        require(referrer!=address(0)&&referrer!=msg.sender,"BAD_REF");
        User storage me=users[msg.sender]; require(me.referrer==address(0),"ALREADY");
        me.referrer=referrer; emit ReferralLinked(referrer,msg.sender);
    }
    function claimReferralReward() external whenNotPaused nonReentrant {
        User storage me=users[msg.sender];
        require(me.referrer!=address(0),"NO_REF"); require(!me.claimedReferral,"CLAIMED");
        me.claimedReferral=true;
        require(token.transferFrom(treasury,msg.sender,referralReward),"PAY_REF_FAIL1");
        require(token.transferFrom(treasury,me.referrer,referralReward),"PAY_REF_FAIL2");
        emit ReferralRewardPaid(msg.sender,referralReward);
        emit ReferralRewardPaid(me.referrer,referralReward);
    }

    /* ---------------- View ---------------- */
    function userView(address u) external view returns(uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool){
        User memory x=users[u];
        return(x.staked,x.stakeUnlockTime,x.credits,x.superlikes,x.boosts,x.reputation,x.reports,x.staked>=minStake);
    }
}
