pragma solidity =0.5.16;

import './interfaces/ITeeterFactory.sol';
import "./interfaces/ITeeterUnderlyingTop.sol";
import './TeeterUnderlyingTop.sol';
import './TeeterLeverage.sol';
import './interfaces/ITeeterLeverage.sol';
import './interfaces/IUniswapV2Factory.sol';


contract TeeterFactoryTop is ITeeterFactory{
    address public owner;
    //store address of underlying asset pool for search/march by (address, lever, direction) of token ERC20
    mapping(address => mapping(uint8 => mapping(uint8 => address) )) public underAddr;
    address[] public allUnderAddrs;
    /* official
    uint256 public purcRateEn = 10384593717069655473233774772224; //Math.div(Math.encode(2), 1000)
    uint256 public redeeRateEn = 10384593717069655473233774772224;//redeem fee rate 
    uint256 public manaRateEn = 2076918743413931150941750296576; //Math.div(Math.encode(4), 10000);//management fee rate 0.04% for one day   
    uint256 public liquDiscountRateEn = 4932682015608086016519670591389696; //Math.div(Math.encode(95), 100);//discount 95%
    uint256 public ownerRateEn = 519229685853482791676087248093184; //Math.div(Math.encode(1), 10);//discount 95%
    */
    uint256 public purcRateEn;
    uint256 public redeeRateEn;
    uint256 public manaRateEn;
    uint256 public liquDiscountRateEn = 5192296858534827628530496329220096;
    uint256 public ownerRateEn;
    
    address public addrBase = 0x6496d167C3c77d31D085CBB6B5396AF7686D98D7;//kovan decimals 6
    //address public addrBase = 0x302648dA807a35A008bAcF082d4E32DD430968DF;//local decimals 4
    //token limit todo
    mapping (address => bool) public tokenTops;
    //token limit end

    function updateParameterForUpcoming(
        uint256 _purcRateEn, uint256 _redeeRateEn, uint256 _manaRateEn, uint256 _liquDiscountRateEn,
        uint256 _ownerRateEn, address _addrBase
        )external {
        require(msg.sender == owner, "TeeterFactory: FORBIDDEN");
        purcRateEn = _purcRateEn;
        redeeRateEn = _redeeRateEn;
        manaRateEn = _manaRateEn;
        liquDiscountRateEn = _liquDiscountRateEn;
        ownerRateEn = _ownerRateEn;
        addrBase = _addrBase;
    }

    function setTopToken(address _token, bool _bool)external{
        require(msg.sender == owner, "TeeterFactory: FORBIDDEN");
        tokenTops[_token] = _bool;
    }
    
    constructor(address _owner) public{
        owner = _owner;
        tokenTops[0x63de620d0f7A89d2728684368720C190eE24e5aF]=true;//kovan BAL
        tokenTops[0x0fD8E8963F564cB8095ca951616e0b6f20FE7d03]=true;//kovan BAT        
        /*
        tokenTops[0x4C125c9A2840A03e70da7C90e514bfB66C36683d]=true;//local BAT
        tokenTops[0xeEB746699f49b787Ab379D848B373e319278e20A]=true;//local QQ10
        tokenTops[0x44DF82EA0caf611Aad6FA56C1709D5299E945375]=true;//local JJ10    
        */
    }


    function allUnderAddrsLength() external view returns (uint) {
        return allUnderAddrs.length;
    } 
    /**
     * @dev get underlying address by start and count 
     */
    // function getUnderlyingAddresses(uint256 start, uint256 count) public view returns (address[] memory) {
    //     uint256 length = allUnderAddrs.length;
    //     if (length == 0) {
    //         // Return an empty array
    //         return new address[](0);
    //     } else {
    //         uint256 end = start + count;
    //         if(length < end) {
    //             end = length;
    //         }
    //         if(start >= end) {
    //             return new address[](0);
    //         }
    //         count = end - start;
    //         address[] memory result = new address[](count);
    //         uint256 index;
    //         for (index = start; index < end; index++) {
    //             result[index - start] = allUnderAddrs[index];
    //         }
    //         return result;
    //     }
    // }
    
    function createUnderlying(
        address token0, uint8 lever, uint8 direction) 
    external returns (address underlying, address leverage){
        require(tokenTops[token0], "Teeter: NOTINLIST");
        //token0 address can not be 0
        require(token0 != address(0), 'Teeter: ZERO_ADDRESS');
        //sure that (token, lever, direction) has not exists
        require(underAddr[token0][lever][direction] == address(0), 'Teeter: UNDERLYING_EXISTS');
        // get underLying contract address code of hash
        bytes memory bytecode = type(TeeterUnderlyingTop).creationCode;
        // get lever contract address code of hash
        bytes memory bytecodeLever = type(TeeterLeverage).creationCode;
        //salt for creadte contract
        bytes32 salt = keccak256(abi.encodePacked(token0, lever, direction));
        //for safe address of salt ensure the salt is uni. imp in future
        //bytes32 newsalt = keccak256(abi.encodePacked(salt, msg.sender)); 
        //inline Assembly for create contracts by create2 method
        assembly {
            underlying := create2(0, add(bytecode, 32), mload(bytecode), salt)
            leverage := create2(0, add(bytecodeLever, 32), mload(bytecodeLever), salt)
        }
        address uniPair;
        uniPair = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).getPair(addrBase, token0);//kovan uniV2Facory
        
        //init the underLying contract by initialize()
        ITeeterUnderlyingTop(underlying).initialize(
            token0, 3, 1,
            leverage, purcRateEn, redeeRateEn, manaRateEn, 
            addrBase, liquDiscountRateEn, ownerRateEn, uniPair);
        //init the leverage contract by initialize()
        ITeeterLeverage(leverage).initialize(underlying);
        //add the address of underLying contract to underAddr
        underAddr[token0][lever][direction] = underlying;
        allUnderAddrs.push(underlying);
        
    }
}
