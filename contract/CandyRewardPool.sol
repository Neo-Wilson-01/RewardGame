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
}

interface ERC20Token {
  function balanceOf(address) external view returns (uint256);
  function transferFrom(address, address, uint256) external returns (bool);
  function transfer(address _to, uint256 _value) external returns (bool success);
}

interface CandyPrinPoolInterface{
    function RechargeReward(address cnAddr,address plyAddr,uint256 amount) external;
    function isRegisteredPlayer(address plyAddr) view external returns(bool result);
}

interface TokenAddrManagerInterface{
    function getRegCoinID(address coinAddr) external view returns(bool result,uint256 coinId);
}

contract CandyReward{

    using SafeMath for *;
    /************************************************************************
     * data  define
     * **********************************************************************/

    TokenAddrManagerInterface tokenManager; //= TokenAddrManager(0xDA46e01bE232Fe0332d01cf4d75CB67Ff783C526);

    //contract
    address constant trueCoinAddr = address(0xfFf0000000000000000000000000000000000000);
    address public _owner;
    address private _manager;
    address payable public _candyPrinPoolAddr; // principal pool contract address
    mapping(uint256 => uint256) public _TotalBalance; // coin type => balance all contract


    //player
    enum RewardType {R_undefine,Recommand_New,Recoomand_Self,Winning_Rec,Wining_Self} //all reward type start is 1, zero not use

    struct Reward{
        address r_Player; //reward player
        RewardType   r_RewardType;// reward type
        uint256 r_CoinType; // reward type
        uint256 r_TotalReward; // total reward
        uint256 r_CurrentReward;//current reward
        uint256 r_lockReward;// lock reward over reward
        bytes32   r_Remark;// mark the info
        // remark is use for mark someing there have rule
        // 0x0000000000000000000000000000000000000000000000000000000000000000
        // the end 20 bytes is use for address who recommand address ca35b7d915458ef540ade6068dfe2f44e8fa733c
            /*0x000000000000000000000000ca35b7d915458ef540ade6068dfe2f44e8fa733c*/
        // the 21-24 bytes is use for Timestamp  5D43A7AA
            /*0x00000000000000005d43a7aaca35b7d915458ef540ade6068dfe2f44e8fa733c*/
    }

    mapping(bytes32 => Reward) public _reward_Info; // hash(r_player,r_RewardType,r_Remark)=>reward;
    mapping(address => mapping(uint256 => uint256)) private _plyTotalReward;// total reward  // ply=>coin type => balance
    mapping(address => mapping(uint256 => uint256)) private _plyCurrentReward;// current reward  // ply=>coin type => balance
    mapping(address => mapping(uint256 => uint256)) private _plyLockRward; // player lock rewar // ply =>coin type => balance

    /************************************************************************
     * function  define
     * **********************************************************************/

    // contract
    constructor(address payable candypPoolAddr,address tManagerAddr)
        public
    {
        require(candypPoolAddr != address(0),"address can not be zero");
        _owner = msg.sender;
        _candyPrinPoolAddr = candypPoolAddr;
        tokenManager = TokenAddrManagerInterface(tManagerAddr);
    }

    /**
     * @dev only manager address can do
     */
    modifier OnlyManager(){
        require(msg.sender == _manager,"must manager have purview");
        _;
    }

    /**
     * @dev set manager address
     * @param manargeAddr manager address
     */
    function setManager(address manargeAddr)
        public
    {
        require(msg.sender == _owner,"only owner can set Manarger" );
        require(manargeAddr != address(0),"address can not set zero");

        _manager = manargeAddr;
    }

    /**
     * @dev set player reward detail info
     * @param plyaddr who win the reward
     * @param RwdType reward type there have 4 type
     * @param CnAddr what is contract coin for reward
     * @param TotalRwd total reward
     * @param LockRwd lock reward
     * @param CurrentRwd release reward player can withdraw
     * @param mark description the reward info
     */
    function setRewardInfo(address plyaddr,
        RewardType RwdType,
        address CnAddr,
        uint256 TotalRwd,
        uint256 LockRwd,
        uint256 CurrentRwd,
        bytes32 mark )
        public
        OnlyManager
    {

        uint256 cnType;
        bool res;
        (res,cnType) = getRegCoinID(CnAddr);
        require(res,"coin addr not exit");

        internal_setRwdInfo(plyaddr,RwdType,cnType,TotalRwd,LockRwd,CurrentRwd,mark);
    }

    /**
     * @dev multi set player reward detail info
     * @param plyaddr who win the reward
     * @param RwdType reward type there have 4 type
     * @param CnAddr what is contract coin for reward
     * @param TotalRwd total reward
     * @param LockRwd lock reward
     * @param CurrentRwd release reward player can withdraw
     * @param mark description the reward info
     */
    function setMultiRewardInfo(address[] memory plyaddr,
        RewardType[] memory RwdType,
        address[] memory CnAddr,
        uint256[] memory TotalRwd,
        uint256[] memory LockRwd,
        uint256[] memory CurrentRwd,
        bytes32[] memory mark )
        public
        OnlyManager
    {
        uint256 len = plyaddr.length;
        require(RwdType.length == len && CnAddr.length == len && TotalRwd.length == len && CurrentRwd.length == len && mark.length == len,"not the same of all param length");
        uint256 cnType;
        bool res;
        for (uint256 i=0;i<len;i++){
            (res,cnType) = getRegCoinID(CnAddr[i]);
            require(res,"coin addr not exit");
            internal_setRwdInfo(plyaddr[i],RwdType[i],cnType,TotalRwd[i],LockRwd[i],CurrentRwd[i],mark[i]);
        }
    }

    /**
     * @dev recharge contract coin reward to this contract
     * @param fromAddr from address after  approve
     * @param coinAddr contract coin address
     * @param amount amount for contract coin
     */
    function TransferReward(address fromAddr,address coinAddr, uint256 amount)
        public
        OnlyManager
    {
        require(amount != 0,"can not transfer zero");

        uint256 cnType;
        bool res;
        (res,cnType) = getRegCoinID(coinAddr);
        require(res,"coin addr not exit");

        if (ERC20Token(coinAddr).transferFrom(fromAddr,address(this), amount)){
            _TotalBalance[cnType]  = _TotalBalance[cnType].add(amount);
        }
    }

    /**
     * @dev transfer true reward to contract
     */
    function transferTrue()
        public
        payable
    {
        _TotalBalance[1] = _TotalBalance[1].add(msg.value);
    }

    /**
     * @dev get player reward info
     * @param plyAddr player address
     * @param coinAddr contract coin address
     * @return currentRwd current reward is can withdraw reward
     * @return totalRwd total win reward
     * @return lockRwd lock reward
     */
    function getPlayerRewardInfo(address plyAddr,address coinAddr)
        public
        view
        returns(uint256 totalRwd,uint256 currentRwd,uint256 lockRwd)
    {

        uint256 cnType;
        bool res;
        (res,cnType) = getRegCoinID(coinAddr);
        if (!res){
            return(totalRwd,currentRwd,lockRwd);
        }

        currentRwd = _plyCurrentReward[plyAddr][cnType];
        totalRwd = _plyTotalReward[plyAddr][cnType];
        lockRwd = _plyLockRward[plyAddr][cnType];
    }

    /**
     * @dev get player reward detail info
     * @param plyaddr player address
     * @param RwdType reward type
     * @param CnAddr contract address
     * @param Mark detail mark for reward
     * @return plyaddr_ player address
     * @return RwdType_ reward type
     * @return CnType_ contract coin type
     * @return totalRwd_ this reward info total reward
     * @return lockReward_ this reward info lock reward
     * @return currentRwd_ this reward info current reward
     * @return Mark_  detail mark for reward
     */
    function getRewardDetail(address plyaddr,RewardType RwdType,address CnAddr,bytes32 Mark)
        public
        view
        returns(address plyaddr_,
            RewardType RwdType_,
            uint256 CnType_,
            uint256 totalRwd_,
            uint256 lockReward_,
            uint256 currentRwd_,
            bytes32 Mark_)
    {

        uint256 cnType;
        bool res;
        (res,cnType) = getRegCoinID(CnAddr);
        require(res,"coin addr not exit");

        bytes32 rwdId = keccak256(abi.encodePacked(plyaddr, RwdType, cnType, Mark));
        address rwdAddr =  _reward_Info[rwdId].r_Player;
        if(rwdAddr != address(0)){

           plyaddr_ = _reward_Info[rwdId].r_Player;
           RwdType_ = _reward_Info[rwdId].r_RewardType;
           CnType_ = _reward_Info[rwdId].r_CoinType;
           totalRwd_ = _reward_Info[rwdId].r_TotalReward;
           lockReward_ =_reward_Info[rwdId].r_lockReward;
           currentRwd_ = _reward_Info[rwdId].r_CurrentReward;
           Mark_ = _reward_Info[rwdId].r_Remark;
        }
    }

    /**
     * @dev Withdraw current reward
     * @param coinAddr contract coin address
     */
    function WithdrawReward(address coinAddr)
        public
    {

        uint256 cnType;
        bool res;
        (res,cnType) = getRegCoinID(coinAddr);
        require(res,"coin addr not exit");

        uint256 currentRwd = _plyCurrentReward[msg.sender][cnType];
        uint256 totalRwd = _TotalBalance[cnType];
        uint256 plyTotalRwd = _plyTotalReward[msg.sender][cnType];

        require(currentRwd<= totalRwd && currentRwd !=0 && currentRwd<=plyTotalRwd,"not engouht reward");

        _plyCurrentReward[msg.sender][cnType] = 0;
        _TotalBalance[cnType] = _TotalBalance[cnType].sub(currentRwd);
        _plyTotalReward[msg.sender][cnType] = _plyTotalReward[msg.sender][cnType].sub(currentRwd);


        if (cnType == 1){
            _candyPrinPoolAddr.transfer(currentRwd);
            CandyPrinPoolInterface(_candyPrinPoolAddr).RechargeReward(trueCoinAddr,msg.sender,currentRwd);
        }else{
            if(!ERC20Token(coinAddr).transfer(_candyPrinPoolAddr,currentRwd)){
                _plyCurrentReward[msg.sender][cnType] = currentRwd;
                _TotalBalance[cnType] = _TotalBalance[cnType].add(currentRwd);
                _plyTotalReward[msg.sender][cnType] =  _plyTotalReward[msg.sender][cnType].add(currentRwd);
            }else{
                CandyPrinPoolInterface(_candyPrinPoolAddr).RechargeReward(coinAddr,msg.sender,currentRwd);
            }
        }

    }

    /**
     * @dev get this contruct balance
     * @param coinAddr contract coin address
     */
    function getContractBalance(address coinAddr)
        public
        view
        OnlyManager
        returns(uint256 balance)
    {
        balance = 0;
        uint256 cnType;
        bool res;
        (res,cnType) = getRegCoinID(coinAddr);
        if (!res){
            return (balance);
        }

        if(cnType == 1){
            balance = address(this).balance;
        }else{
            balance = ERC20Token(coinAddr).balanceOf(address(this));
        }
    }

    /**
     * @dev go back unuse reward
     * --- only owner can do
     * @param plyAddr_ who receive the unuse reward
     * @param coinAddr contract coin address
     * @param amount coin amount
     */
    function backReward(address payable plyAddr_,address coinAddr,uint256 amount) public {
        require(msg.sender == _owner,"only owner can get");
        bool res;
        uint256 cnType;
        (res,cnType) = getRegCoinID(coinAddr);
        require(res,"coin addr not exit");

        uint256 balance = _TotalBalance[cnType];
        require(balance>=amount,"not engouht balance");
        _TotalBalance[cnType] = _TotalBalance[cnType].sub(amount);
        if (cnType == 1){
            plyAddr_.transfer(amount);
        }else{
            if(!ERC20Token(coinAddr).transfer(plyAddr_,amount)){
                _TotalBalance[cnType] = _TotalBalance[cnType].add(amount);
            }
        }
    }

    /**
     * @dev change candy principal pool address
     * --- only owner can do
     * @param cppAddr candy principal pool contruct address
     */
    function changeCandyPrinAddr(address payable cppAddr ) public {
        require(msg.sender == _owner,"only owner can set");
        require(cppAddr != address(0),"can not be zero");
        uint256 size;
        // solium-disable-next-line security/no-inline-assembly
        assembly { size := extcodesize(cppAddr) }
        require(size>0,"must contruct  address");
        _candyPrinPoolAddr = cppAddr;
    }

    /**
     * @dev get coinID by contruct coin address
     * @param coinAddr contruct address
     * @return result true is have coinID ,false is not add to tokenAddrManager contruct
     * @return cnType coin Type
     */
    function getRegCoinID(address coinAddr)
        internal
        view
        returns(bool result,uint256 cnType)
    {
        (result,cnType) = tokenManager.getRegCoinID(coinAddr);
    }

    /**
     * @dev get coinID by contruct coin address
     * @param plyaddr who win the reward
     * @param RwdType reward type there have 4 type
     * @param CnType what is contract coin for reward
     * @param TotalRwd total reward
     * @param LockRwd lock reward
     * @param CurrentRwd release reward player can withdraw
     * @param Mark description the reward info
     */
    function internal_setRwdInfo(
        address plyaddr,
        RewardType RwdType,
        uint256 CnType,
        uint256 TotalRwd,
        uint256 LockRwd,
        uint256 CurrentRwd,
        bytes32 Mark)
        private
    {
        require(RwdType>=RewardType.Recommand_New && RwdType <= RewardType.Wining_Self,"rwd Type not exit");
        require(TotalRwd !=0  ," reward can not be zero" );

        bool isRegPlayer = CandyPrinPoolInterface(_candyPrinPoolAddr).isRegisteredPlayer(plyaddr);
        require(isRegPlayer,"not registered player");

        bytes32 rwdId = keccak256(abi.encodePacked(plyaddr, RwdType, CnType, Mark));
        address rwdAddr =  _reward_Info[rwdId].r_Player;
        uint256 totalReward = _reward_Info[rwdId].r_TotalReward;

        if (rwdAddr == address(0)){
             // new one

            _reward_Info[rwdId] = Reward(
                plyaddr,
                RwdType,
                CnType,
                TotalRwd,
                LockRwd,
                CurrentRwd,
                Mark
            );

            // add total balance
            _plyTotalReward[plyaddr][CnType] = _plyTotalReward[plyaddr][CnType].add(TotalRwd);
            _plyLockRward[plyaddr][CnType] = _plyLockRward[plyaddr][CnType].add(LockRwd);

        }else{
            require(TotalRwd ==totalReward,"not seam total reward");
            _reward_Info[rwdId].r_CurrentReward = CurrentRwd;
            _reward_Info[rwdId].r_lockReward = LockRwd;
            _plyLockRward[plyaddr][CnType] = _plyLockRward[plyaddr][CnType].sub(CurrentRwd);
        }

        // add current reward who can withdraw
        _plyCurrentReward[plyaddr][CnType] =  _plyCurrentReward[plyaddr][CnType].add(CurrentRwd);
    }


}