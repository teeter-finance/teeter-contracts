pragma solidity =0.5.16;

import './interfaces/ITeeterFactory.sol';
import "./interfaces/ITeeterUnderlyingTop.sol";
import './TeeterUnderlyingTop.sol';
import './TeeterLeverage.sol';
import './interfaces/ITeeterLeverage.sol';
import './interfaces/IUniswapV2Factory.sol';


contract TeeterFactoryTop is ITeeterFactory{
    address public owner;
    mapping(address => mapping(uint8 => mapping(uint8 => address) )) public underAddr;
    address[] public allUnderAddrs;
    uint256 public purcRateEn;
    uint256 public redeeRateEn;
    uint256 public manaRateEn;
    uint256 public liquDiscountRateEn = 5192296858534827628530496329220096;
    uint256 public ownerRateEn;
    address public addrBase = 0x6496d167C3c77d31D085CBB6B5396AF7686D98D7;//kovan decimals 6
    mapping (address => bool) public tokenTops;

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
    }


    function allUnderAddrsLength() external view returns (uint) {
        return allUnderAddrs.length;
    } 

    function createUnderlying(
        address token0, uint8 lever, uint8 direction) 
    external returns (address underlying, address leverage){
        require(tokenTops[token0], "Teeter: NOTINLIST");
        require(token0 != address(0), 'Teeter: ZERO_ADDRESS');
        require(underAddr[token0][lever][direction] == address(0), 'Teeter: UNDERLYING_EXISTS');
        bytes memory bytecode = type(TeeterUnderlyingTop).creationCode;
        bytes memory bytecodeLever = type(TeeterLeverage).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, lever, direction));
        assembly {
            underlying := create2(0, add(bytecode, 32), mload(bytecode), salt)
            leverage := create2(0, add(bytecodeLever, 32), mload(bytecodeLever), salt)
        }
        address uniPair;
        uniPair = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).getPair(addrBase, token0);//kovan uniV2Facory
        
        ITeeterUnderlyingTop(underlying).initialize(
            token0, 3, 1,
            leverage, purcRateEn, redeeRateEn, manaRateEn, 
            addrBase, liquDiscountRateEn, ownerRateEn, uniPair);
        ITeeterLeverage(leverage).initialize(underlying);
        underAddr[token0][lever][direction] = underlying;
        allUnderAddrs.push(underlying);
    }
}
