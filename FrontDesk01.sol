pragma solidity =0.5.16;

import './interfaces/ITeeterFactory.sol';
import './interfaces/ITeeterUnderlying.sol';
import './interfaces/ITeeterUnderlyingTop.sol';
import './interfaces/ITeeterLeverage.sol';
import './interfaces/IFrontDesk01.sol';
import './interfaces/IWETH.sol';
import './libraries/AddrLibrary.sol';
import './libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Factory.sol';
import './libraries/TeeterLibrary.sol';

contract FrontDesk01 is IFrontDesk01{
    //defined address of factory contract
    address public factory;
    address public factoryTop;
    //defined address of WETH contract
    address public WETH ;
    address public addrUNIFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;//kovan
   //ensure the deal be done in time for price is right
    modifier ensure(uint256 deadline) { 
        //comment for local test
        require(deadline >= block.timestamp, "FrontDesk01: EXPIRED");//kovan
        _;
    }

    constructor(address _factory, address _factoryTop) public{
        factory = _factory;
        factoryTop = _factoryTop;
        WETH = 0x021861cC8d0Ad95C1C7E8BA77517bA9344e9a64F; //kovan
        //WETH = 0x889c62611e63755536c141D0966834c4B0C4441A; //local
    }

    function depositTop(
        address token0, uint256 amt, address to, uint256 deadline
        ) external ensure(deadline) returns(uint256 liquidity){
        uint8 initLever = 3;
        uint8 direction = 1;
        address underlying;
        require(ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: NOTTOP");
        //create the underlying contract if doesn't exist
        if(ITeeterFactory(factoryTop).underAddr(token0, initLever, direction) == address(0)){
            ITeeterFactory(factoryTop).createUnderlying(token0, initLever, direction);
        }
        underlying = AddrLibrary.underlyingTopFor(factoryTop, token0, initLever, direction);
        address addrBase = ITeeterFactory(factoryTop).addrBase();
        TransferHelper.safeTransferFrom(addrBase, msg.sender, underlying, amt);
        liquidity = ITeeterUnderlyingTop(underlying).mint(to);
    }

    //param amt, if token0 is top amt is amount of base, if token0 is not top amt is amount of token0
    function deposit(
        address token0, uint256 amt, address to, uint256 deadline
        ) external ensure(deadline) returns(uint256 liquidity){
        require(!ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: ISTOP");
        uint8 initLever = 3;
        uint8 direction = 1;
        address underlying;
        //create the underlying contract if doesn't exist
        if(ITeeterFactory(factory).underAddr(token0, initLever, direction) == address(0)){
            ITeeterFactory(factory).createUnderlying(token0, initLever, direction);
        }
        underlying = AddrLibrary.underlyingFor(factory, token0, initLever, direction);
        TransferHelper.safeTransferFrom(token0, msg.sender, underlying, amt);
        liquidity = ITeeterUnderlying(underlying).mint(to);
    }

    function purchaseTop(
        uint256 amtTokenIn, address token0, address to, uint256 deadline
        ) external ensure(deadline) returns (uint256 amtLever) {
        require(ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: NOTTOP");
        require(amtTokenIn > 0, "TEETER FrontDesk01: INSUFFICIENT_AMOUNT");
        address underlying;
        uint8 initLever = 3;
        uint8 direction = 1;
        underlying = AddrLibrary.underlyingTopFor(factoryTop, token0, initLever, direction);
        address addrBase = ITeeterUnderlyingTop(underlying).addrBase();
        //transfer token0 from msg.sender to underlying contract
        TransferHelper.safeTransferFrom(
            addrBase,
            msg.sender,
            underlying,
            amtTokenIn
        );
        amtLever = ITeeterUnderlyingTop(underlying).purchase(to);
    }

    function purchase(
        uint256 amtTokenIn, address token0, address to, uint256 deadline
        ) external ensure(deadline) returns (uint256 amtLever) {
        require(!ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: ISTOP");
        require(amtTokenIn > 0, "TEETER FrontDesk01: INSUFFICIENT_AMOUNT");
        address underlying;
        uint8 initLever = 3;
        uint8 direction = 1;
        underlying = AddrLibrary.underlyingFor(factory, token0, initLever, direction);
        address addrBase = ITeeterUnderlying(underlying).addrBase();
        //transfer token0 from msg.sender to underlying contract
        TransferHelper.safeTransferFrom(
            addrBase,
            msg.sender,
            underlying,
            amtTokenIn
        );
        amtLever = ITeeterUnderlying(underlying).purchase(to);
    }

    function redeemTop(
        uint256 amtLeverIn, address token0, address to, uint256 deadline
        ) public ensure(deadline) returns (uint256 amtToken0, uint256 amtU) {
        require(ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: NOTTOP");
        require(amtLeverIn > 0, "TEETER FrontDesk01: INSUFFICIENT_amtLeverIn");
        address underlying;
        uint8 initLever = 3;
        uint8 direction = 1;
        underlying = AddrLibrary.underlyingTopFor(factoryTop, token0, initLever, direction);
        address leverage = ITeeterUnderlyingTop(underlying).leverage();
        //transfer amtLeverIn leverage to underlying contract for get token0 back
        TransferHelper.safeTransferFrom(
            leverage,
            msg.sender,
            underlying,
            amtLeverIn
        );
        (amtToken0, amtU) = ITeeterUnderlyingTop(underlying).redeem(to);
    }

    function redeem(
        uint256 amtLeverIn, address token0, address to, uint256 deadline
        ) public ensure(deadline) returns (uint256 amtToken0, uint256 amtU) {
        require(!ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: ISTOP");
        require(amtLeverIn > 0, "TEETER FrontDesk01: INSUFFICIENT_amtLeverIn");
        address underlying;
        uint8 initLever = 3;
        uint8 direction = 1;
        underlying = AddrLibrary.underlyingFor(factory, token0, initLever, direction);
        address leverage = ITeeterUnderlying(underlying).leverage();
        //transfer amtLeverIn leverage to underlying contract for get token0 back
        TransferHelper.safeTransferFrom(
            leverage,
            msg.sender,
            underlying,
            amtLeverIn
        );
        (amtToken0, amtU) = ITeeterUnderlying(underlying).redeem(to);
    }



    /**
    * @dev user who add asset for fixed income, transfer liquidity token to underlying contract for asset token return
    * params same as redeem()
    */
    function recycleTop(
        uint256 amtliquIn, address token0, address to, uint256 deadline
        ) public ensure(deadline) returns (uint256 amtToken0, uint256 amtU) {
        require(ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: NOTTOP");
        require(amtliquIn > 0, "TEETER FrontDesk01: INSUFFICIENT_amtliquIn");
        address underlying;
        uint8 initLever = 3;
        uint8 direction = 1;
        underlying = AddrLibrary.underlyingTopFor(factoryTop, token0, initLever, direction);
        TransferHelper.safeTransferFrom(
            underlying,
            msg.sender,
            underlying,
            amtliquIn
        ); 
        (amtToken0, amtU) = ITeeterUnderlyingTop(underlying).recycle(to);
    }

    function recycle(
        uint256 amtliquIn, address token0, address to, uint256 deadline
        ) public ensure(deadline) returns (uint256 amtToken0, uint256 amtU) {
        require(!ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: ISTOP");
        require(amtliquIn > 0, "TEETER FrontDesk01: INSUFFICIENT_amtliquIn");
        address underlying;
        uint8 initLever = 3;
        uint8 direction = 1;
        underlying = AddrLibrary.underlyingFor(factory, token0, initLever, direction);
        TransferHelper.safeTransferFrom(
            underlying,
            msg.sender,
            underlying,
            amtliquIn
        ); 
        (amtToken0, amtU) = ITeeterUnderlying(underlying).recycle(to);
    }



    function liquidation3PartTop(
        uint256 amtUin, address token0, address to, uint256 deadline
        )external ensure(deadline) returns (uint256 amtToken0){
        require(ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: NOTTOP");
        require(amtUin > 0, "TEETER FrontDesk01: INSUFFICIENT_amtUin");
        address underlying;
        uint8 initLever = 3;
        uint8 direction = 1;
        underlying = AddrLibrary.underlyingTopFor(factoryTop, token0, initLever, direction);
        address addrBase = ITeeterUnderlyingTop(underlying).addrBase();
        TransferHelper.safeTransferFrom(
            addrBase,
            msg.sender,
            underlying,
            amtUin
        );     
        amtToken0 = ITeeterUnderlyingTop(underlying).liquidation3Part(to); 
    }

    function liquidation3Part(
        uint256 amtUin, address token0, address to, uint256 deadline
        )external ensure(deadline) returns (uint256 amtToken0){
        require(!ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: ISTOP");
        require(amtUin > 0, "TEETER FrontDesk01: INSUFFICIENT_amtUin");
        address underlying;
        uint8 initLever = 3;
        uint8 direction = 1;
        underlying = AddrLibrary.underlyingFor(factory, token0, initLever, direction);
        address addrBase = ITeeterUnderlying(underlying).addrBase();
        TransferHelper.safeTransferFrom(
            addrBase,
            msg.sender,
            underlying,
            amtUin
        );     
        amtToken0 = ITeeterUnderlying(underlying).liquidation3Part(to); 
    }

    function liquidationLPTTop(
        uint256 amtLPTin, address token0, address to, uint256 deadline
        )public ensure(deadline) returns (uint256 amtToken0, uint256 amtU){
        require(ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: NOTTOP");
        require(amtLPTin > 0, "TEETER FrontDesk01: INSUFFICIENT_amtLPTin");
        address underlying;
        uint8 initLever = 3;
        uint8 direction = 1;
        underlying = AddrLibrary.underlyingTopFor(factoryTop, token0, initLever, direction);
        TransferHelper.safeTransferFrom(
            underlying,
            msg.sender,
            underlying,
            amtLPTin
        );     
        (amtToken0, amtU) = ITeeterUnderlyingTop(underlying).liquidationLPT(to); 
    }

    function liquidationLPT(
        uint256 amtLPTin, address token0, address to, uint256 deadline
        )public ensure(deadline) returns (uint256 amtToken0, uint256 amtU){
        require(!ITeeterFactory(factoryTop).tokenTops(token0), "TEETER FrontDesk01: ISTOP");
        require(amtLPTin > 0, "TEETER FrontDesk01: INSUFFICIENT_amtLPTin");
        address underlying;
        uint8 initLever = 3;
        uint8 direction = 1;
        underlying = AddrLibrary.underlyingFor(factory, token0, initLever, direction);
        TransferHelper.safeTransferFrom(
            underlying,
            msg.sender,
            underlying,
            amtLPTin
        );     
        (amtToken0, amtU) = ITeeterUnderlying(underlying).liquidationLPT(to); 
    }
}