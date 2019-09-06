pragma solidity  ^0.5.7;


// safe math
library SafeMath {

    function sub(uint256 a, uint256 b)
    internal
    pure
    returns (uint256)
    {
        require(b <= a, "SafeMath sub failed");
        return a - b;
    }

    function add(uint256 a, uint256 b)
    internal
    pure
    returns (uint256 c)
    {
        c = a + b;
        require(c >= a, "SafeMath add failed");
        return c;
    }

    function mul(uint256 a, uint256 b)
    internal
    pure
    returns (uint256 c)
    {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        require(c / a == b, "SafeMath mul failed");
        return c;
    }

}

interface ERC20Token {
  function transfer(address _to, uint256 _value) external returns (bool success);
}

interface TokenAddrManagerInterface{
    function addNewCoinAddr(address coinAddr) external;
    function getRegCoinID(address coinAddr) external view returns(bool result,uint256 coinId);
}

contract CandyPrinPool{
    using SafeMath for *;
    /************************************************************************
     * data  define
     * **********************************************************************/

    TokenAddrManagerInterface tokenManager;

    //contract
    address constant trueCoinAddr = address(0xfFf0000000000000000000000000000000000000);
    address private _owner; // owner address
    address private _manager; // manager address
    address public _rewardPoolAddr;// reward pool contract address

    mapping(uint256 =>uint256)  public _fee; // team fee can set
    mapping(uint256=>uint256) public _rechargeThreshold; // recharge minimum threshold
    mapping(uint256=>uint256) public _withdarwThreshold; // withdraw minimum threshold


    //manage
    address payable  private _teamFeeAdder ;  // team fee address
    mapping(uint256 => uint256) private _TotalBalance; // coin type => balance all contract

    //player
    uint256 public  _P_ID; //this is the player ID
    mapping(address=>uint256) private _plyID; // player address=> ID
    mapping(address=>mapping(uint256=>uint256)) private _plyBalance; // player Different（true ABC）total balance  address=>coin number->balance
    mapping(address=>mapping(uint256=>uint256)) private _PlyActiveBalance;//player Different（true ABC）Active balance address=>coin number->active balance
    mapping(address=>mapping(uint256=>uint256)) private  _plyLockBalance;// player Different（true ABC）Lock balance  address=>coin number->lock balance

    // add safe switch
    bool private _isStopWithdraw; // stop withdraw switch
    mapping(address=>bool)  private _isPlyStopWithdraw; // bad player withdraw switch

    // add backup info
    struct Player{
        uint256 p_plyID;
        mapping(bytes32=>bytes32) p_backupInfo;
    }
    mapping(address=>Player) _playBackUpInfo; // only for backup

    /************************************************************************
     * function  define
     * **********************************************************************/
    constructor(address payable teamFee,address tManagerAddr)
        public
    {
        require(teamFee != address(0),"teamFee address can not be zero");

        _teamFeeAdder = teamFee;
        _owner = msg.sender;

        tokenManager = TokenAddrManagerInterface(tManagerAddr);

    }

    /**
     * @dev only manager can do
     */
    modifier OnlyManager(){
        require(msg.sender == _manager,"must manager have purview");
        _;
    }

    /**
     * @dev fallback function receive true from reward pool CandyRewardPool.sol
     */
    function() payable external{
        require(msg.sender == _rewardPoolAddr, "only _rewardPool can add");
    }

    /**
     * @dev set manarger address
     * @param manargeAddr what is manarger address
     */
    function setManager(address manargeAddr)
        public
    {
        require(msg.sender == _owner,"only owner can set Manarger" );
        require(manargeAddr != address(0),"address can not set zero");

        _manager = manargeAddr;
    }

    /**
     * @dev CandyRewardPool.sol contract address
     * @param rewardAddr what is reward pool contract address
     */
    function setCandyRewardAdd(address rewardAddr)
        public
        OnlyManager
    {
        require(rewardAddr != address(0),"address can not set zero");

        _rewardPoolAddr = rewardAddr;
    }

    /**
     * @dev add a new coin contract address
     * @param coinAddr what is reward pool contract address
     */
    function AddNewCoin(address coinAddr)
        public
        OnlyManager
    {
        tokenManager.addNewCoinAddr(coinAddr);
    }

    /**
     * @dev recharge reward coin to this contract
     * --this function only reward pool can use
     * --set _rewardPoolAddr when use this function
     * @param cnAddr what is coin contract address
     * @param plyAddr what is player  address
     * @param amount what is amount coin to this contract
     */
    function RechargeReward(address cnAddr,address plyAddr,uint256 amount)
        public
    {
        require(_rewardPoolAddr != address(0) ,"pls set reward pool address");
        require(msg.sender == _rewardPoolAddr,"only reward pool can use this function");

       //get coin type
       uint256 cnType = 0;
       bool res;
       (res,cnType) = tokenManager.getRegCoinID(cnAddr);
       require(res,"coin not exit");

        RechargeCoin(cnType,plyAddr,amount);
    }

    /**
     * @dev player recharge true to this contract
     */
    function RechargeTrue()
        public
        payable
    {
        require(msg.value >= _rechargeThreshold[1],"can not recharge less then thold");
        RechargeCoin(1,msg.sender,msg.value);
    }

    /**
     * @dev manager get the player already recharge contract coin to this contract then set player balance
     * --player must transfer contract coin to this contract
     * --manager check player already recharged then use this function
     * @param coinAddr what is coin contract address
     * @param plyAddr what is player  address
     * @param amount what is amount coin to this contract
     */
    function RechargeOtherCoin(address coinAddr,address plyAddr,uint256 amount)
        public
        OnlyManager
    {
       //get coin type
       uint256 cnType = 0;
       bool res;
       (res,cnType) = tokenManager.getRegCoinID(coinAddr);
       require(res,"coin not exit");

        require(amount >= _rechargeThreshold[cnType],"OtherCoin can not recharge less then thold");
        RechargeCoin(cnType, plyAddr, amount);
    }

    /**
     * @dev manager can lock or unlock palyer balance
     * ---lock must is lock  active balance
     * ---unlock must is unlock lock balance
     * @param plyAddr lock/unlock who is balance
     * @param amount lock/unlock amount
     * @param coinAddr lock/unlock what is kind of coin
     * @param isLock lock or unlock
     * @return result lock or unlock true or false
     */
    function setPlayerLockBalance(address plyAddr,uint256 amount,address coinAddr,bool isLock)
        public
        OnlyManager
        returns( bool result)
    {
        if(amount ==0){
            result = false;
            return result;
        }

        require(amount !=0,"can not recharge zero");
        uint256 pid = _plyID[plyAddr];

        require(pid != 0 && pid <= _P_ID,"ply not exit");

        //get coin type
       uint256 cnType = 0;
       bool res;
       (res,cnType) = tokenManager.getRegCoinID(coinAddr);
       require(res,"coin not exit");

        uint256  plyLockB = _plyLockBalance[plyAddr][cnType];
        uint256  plyActiveB = _PlyActiveBalance[plyAddr][cnType];

        result = checkBalance(plyAddr,cnType);

        if (!result){
            return result;
        }

        if(isLock){
            // lock
            require(plyActiveB>=amount,"not enough active balance");
            _plyLockBalance[plyAddr][cnType] += amount;
            _PlyActiveBalance[plyAddr][cnType] -= amount;
        }else{
            // unlock
            require(plyLockB >=amount ,"not enough lock balance");
            _plyLockBalance[plyAddr][cnType] -= amount;
            _PlyActiveBalance[plyAddr][cnType] += amount;
        }

        result = true;
    }


    /**
     * @dev player withdraw
     * ---withdraw the active balance
     * @param cnAddr contract coin contract address
     * @param amount withdraw amount
     */
    function withdraw(address cnAddr,uint256 amount)
        public
    {
        require(!_isStopWithdraw,"already stop all withdraw");
        require(!_isPlyStopWithdraw[msg.sender],"already stop withdraw");

        uint256 pid = _plyID[msg.sender];
        require((pid !=0 && pid <= _P_ID) && amount !=0 ,"player not exit or amount is zero");

       //get coin type
       uint256 cnType = 0;
       bool res;
       (res,cnType) = tokenManager.getRegCoinID(cnAddr);
       require(res,"coin not exit");

        require(amount >= _withdarwThreshold[cnType],"must withdraw big then _withdarwThreshold");

        uint256 plyActiveB = _PlyActiveBalance[msg.sender][cnType];
        uint256 plyTotalB = _plyBalance[msg.sender][cnType];

        require(amount<=plyActiveB && amount <= plyTotalB,"not enough balance");

        _PlyActiveBalance[msg.sender][cnType] = _PlyActiveBalance[msg.sender][cnType].sub(amount);
        _plyBalance[msg.sender][cnType] = _plyBalance[msg.sender][cnType].sub(amount);
        _TotalBalance[cnType] = _TotalBalance[cnType].sub(amount);

        //fee calc
        uint256 actual_amount = amount.mul(100 - _fee[cnType])/100;
        uint256 actual_fee = amount.mul(_fee[cnType])/100;

        require(actual_amount<=plyActiveB && actual_amount <= plyTotalB,"not enough actual_amount balance");

        if (cnType == 1){
            _teamFeeAdder.transfer(actual_fee);
            msg.sender.transfer(actual_amount);
        }else{

           ERC20Token(cnAddr).transfer(_teamFeeAdder,actual_fee);
           if(!ERC20Token(cnAddr).transfer(msg.sender,actual_amount) ){
                _PlyActiveBalance[msg.sender][cnType] = _PlyActiveBalance[msg.sender][cnType].add(amount);
                _plyBalance[msg.sender][cnType] = _plyBalance[msg.sender][cnType].add(amount);
                _TotalBalance[cnType] = _TotalBalance[cnType].add(amount);
           }
        }

    }

    /**
     * @dev get player balance info
     * @param plyAddr palyer address
     * @param cnAddr contract coin contract address
     * @return totalBalance
     * @return lockBalance
     * @return activeBalance
     */
    function getPlayerInfo(address plyAddr,address cnAddr)
        public
        view
        returns(uint256 totalBalance,uint256 lockBalance,uint256 activeBalance)
    {
        bool res;
        uint256 cnType;
        (res,cnType) = tokenManager.getRegCoinID(cnAddr);
        require(res ,"coin not exit");

        totalBalance = _plyBalance[plyAddr][cnType];
        lockBalance = _plyLockBalance[plyAddr][cnType];
        activeBalance = _PlyActiveBalance[plyAddr][cnType];
    }

    /**
     * @dev set player withdraw minimum threshold
     * @param cnAddr palyer address
     * @param thold minimum threshold
     */
    function setWithdrawThold(address cnAddr,uint256 thold)
        public
        OnlyManager
    {
        bool res;
        uint256 cnType;
        (res,cnType) = tokenManager.getRegCoinID(cnAddr);
        require(res ,"coin not exit");

        _withdarwThreshold[cnType] = thold;
    }

    /**
     * @dev set player recharge minimum threshold
     * @param cnAddr palyer address
     * @param thold  recharge minimum threshold
     */
    function setRechargeThold(address cnAddr,uint256 thold)
        public
        OnlyManager
    {
        bool res;
        uint256 cnType;
        (res,cnType) = tokenManager.getRegCoinID(cnAddr);
        require(res ,"coin not exit");


        _rechargeThreshold[cnType] = thold;
    }


    /**
     * @dev confirm the plyAddr is or not player
     * ---use by reward pool
     * @param plyAddr  who is join the game
     * @return  result  true is palyer, false not join the game
     */
    function isRegisteredPlayer(address plyAddr)
        view
        external
        returns(bool result)
    {
        uint256 pid = _plyID[plyAddr];
        if(pid == 0){
            result = false;
        }else{
            result = true;
        }
    }

    /**
     * @dev set stop withdraw by emergency situations
     * --- only owner can use in emergency situations
     * @param isOpen  true is stop withdraw false is allow withdraw
     */
    function setStopWithdraw(bool isOpen)
        public
    {
        require(msg.sender == _owner,"only owner can set");
        if(isOpen){
            _isStopWithdraw = true;
        }else{
            _isStopWithdraw = false;
        }
    }

    /**
     * @dev set stop Specified palyer withdraw
     * @param plyAddr  stop or allow withdraw palyer address
     * @param isStop  true is stop withdraw false is allow withdraw
     */
    function setPlayerStopWithdraw(address plyAddr,bool isStop)
        public
        OnlyManager
    {
        _isPlyStopWithdraw[plyAddr]=isStop;
    }

    /**
     * @dev set  palyer backup info not use know
     * @param plyAddr  stop or allow withdraw palyer address
     * @param key_  bytes32 key
     * @param value_  bytes32 value
     */
    function setPlayerBackupInfo(address plyAddr,bytes32 key_, bytes32 value_)
        public
        OnlyManager
    {
        uint256 pid = _plyID[plyAddr];
        require(pid != 0,"player not exit");
        _playBackUpInfo[plyAddr].p_plyID = pid;
        _playBackUpInfo[plyAddr].p_backupInfo[key_]=value_;
    }

    /**
     * @dev set  fee
     * ---only manager can set fee
     * @param cnAddr  contract coin address
     * @param feeNum  1 is 1% ,100 is 100%
     */
    function setFee(address cnAddr,uint256 feeNum) public OnlyManager{

        require(feeNum<100,"can not set free percentage 100%");
        bool res;
        uint256 cnType;
        (res,cnType) = tokenManager.getRegCoinID(cnAddr);
        require(res ,"coin not exit");

        _fee[cnType] = feeNum;
    }

    /**
     * @dev recharge coin to contract
     * @param cnType what is coin contract ID that must add tokenAddrManager mapping
     * @param plyAddr what is player  address
     * @param amount what is amount coin to this contract
     */
    function RechargeCoin(uint256  cnType,address plyAddr,uint256 amount)
        private
    {

        uint256 pid = _plyID[plyAddr];
        if (pid ==0){
            //new player
            _P_ID ++;
            _plyID[plyAddr] = _P_ID;
            _plyBalance[plyAddr][cnType] = amount;
            _PlyActiveBalance[plyAddr][cnType] = amount;
            _plyLockBalance[plyAddr][cnType] = 0;

        }else{
            _plyBalance[plyAddr][cnType] = _plyBalance[plyAddr][cnType].add(amount);
            _PlyActiveBalance[plyAddr][cnType] = _PlyActiveBalance[plyAddr][cnType].add(amount);
        }

        _TotalBalance[cnType] = _TotalBalance[cnType].add(amount);
    }

    /**
     * @dev recharge coin to contract
     * @param cnType what is coin contract ID that must add tokenAddrManager mapping
     * @param plyaddr what is player  address
     * @return result true the balance is correct false some is error.
     */
    function checkBalance(address plyaddr , uint256 cnType)
        private
        view
        returns (bool result)
    {
        uint256 actual_all_balance = _plyBalance[plyaddr][cnType];
        uint256 shouldbe_balance = 0;
        uint256 ply_actBalance = _PlyActiveBalance[plyaddr][cnType];
        uint256 ply_lockBalance = _plyLockBalance[plyaddr][cnType];

        shouldbe_balance = ply_actBalance.add(ply_lockBalance);
        if (actual_all_balance == shouldbe_balance){
            result = true;
        }else{
            result = false;
        }

    }

}