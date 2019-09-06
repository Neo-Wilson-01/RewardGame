pragma solidity  ^0.5.7;

contract tokenAddrManager{
    /************************************************************************
     * data  define
     * **********************************************************************/
    address private _owner;

    uint256 public _coinTypeID; // zero not use ,start to 1
    mapping( address => uint256 ) public _coinContractAddr;

    address constant trueCoinAddr = address(0xfFf0000000000000000000000000000000000000);

    uint256 private _trustID;
    mapping(address=>uint256) private _trustList;
    //address[] private _trustList; //who can add new coin to this contract

    /************************************************************************
     * data  define
     * **********************************************************************/

    constructor() public{
        _owner = msg.sender;
        _trustID =1;
        _coinTypeID =1; // 1 is true coin
        _coinContractAddr[trueCoinAddr] = _coinTypeID; //use address(0) for true coin
    }

    /**
     * @dev only CandyPrincipalPool.sol and CandyRewardPool.sol contract
     * can use this contract
     */
    modifier OnlyTrust(){
        uint256 id = _trustList[msg.sender];
        require(id !=0 ,"not trust member");
        _;
    }

    /**
     * @dev add a new  coin contract to mapping the coinID add 1.
     * @param tList what is for CandyPrincipalPool.sol and CandyRewardPool.sol
     */
    function addTrustList(address[] memory tList)
        public
    {
        require(msg.sender == _owner,"only owner can add list");
        uint256 listLen = tList.length;
        for(uint256 i=0;i<listLen;i++){
            address  menberAddr = tList[i];
            require(menberAddr != address(0),"address can not be zero");
            _trustList[menberAddr] = _trustID;
            _trustID++;
        }
    }

    /**
     * @dev add a new  coin contract to mapping the coinID add 1.
     * @param coinAddr coin contract address
     */
    function addNewCoinAddr(address coinAddr)
        external
        OnlyTrust
    {
        require(coinAddr != address(0),"con not set zero addr");
        uint256 coinID = _coinContractAddr[coinAddr];
        if (coinID == 0){
            // new coinID
            _coinTypeID++;
            _coinContractAddr[coinAddr] = _coinTypeID;
        }
    }

    /**
     * @dev judge the coin contract address is or not add the mapping.
     * @param coinAddr coin contract address
     * @return result true is alread add,false not add
     */
    function isRegisteredCoin(address coinAddr)
        external
        view
        returns (bool result)
    {
        uint256 CnID = _coinContractAddr[coinAddr];
        if(CnID>=1 && CnID <= _coinTypeID){
            result = true;
        }else{
            result = false;
        }
    }


    /**
     * @dev use coin contract address to get coinID.
     * @param coinAddr coin contract address
     * @return coinId what is coin address to Coin ID
     */
    function getRegisteredCoinId(address coinAddr)
        external
        view
        returns(uint256 coinID)
    {
        uint256 CnID = _coinContractAddr[coinAddr];
        if(CnID>=1 && CnID <= _coinTypeID){
            coinID = CnID;
        }else{
            CnID = 0;
        }
    }


    /**
     * @dev use coin contract address to get coinID and judge the coin address is or not storage to mapping.
     * @param coinAddr coin contract address
     * @return result what result is coin address is or not in this mapping
     * @return coinId what is coin address to Coin ID
     */
    function getRegCoinID(address coinAddr)
        external
        view
        returns(bool result,uint256 coinId)
    {
        uint256 CnID = _coinContractAddr[coinAddr];
        if(CnID>=1 && CnID <= _coinTypeID){
            result = true;
            coinId = CnID;
        }else{
            result = false;
            CnID = 0;
        }
    }

}