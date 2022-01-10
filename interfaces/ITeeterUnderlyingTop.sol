pragma solidity ^0.5.6;

interface ITeeterUnderlyingTop {


    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function nonces(address owner) external view returns (uint);
    function factory() external view returns (address);
    function leverage() external view returns (address);
    function token0() external view returns (address);
    function capAddU() external view returns (uint256);
    function price0En() external view returns (uint256);
    function priceEn() external view returns (uint256);
    function purcRateEn() external view returns (uint256);
    function redeeRateEn() external view returns (uint256);
    function manaRateEn() external view returns (uint256);
    function liquDiscountRateEn() external view returns (uint256);
    function ownerRateEn() external view returns (uint256);
    function addrBase() external view returns (address);
    function balBaseLast() external view returns (uint256);
    function initLever() external view returns (uint8);
    function direction() external view returns (uint8);
    function status() external view returns (uint8);
    function ownerU() external view returns (uint256);//local
    function exePrice() external view returns (uint256);//for test
    function exchangeAddrs(uint) external view returns (address);//for test
    function blockTimestampInit() external view returns (uint);

    function updatePrice()external;

    function getReserves() external view returns (
        uint256 _fundSoldValueEn, 
        uint256 _fundSoldQTY, 
        uint256 _nvEn, 
        uint256 _presLeverEn, 
        uint256 _underlyingU,
        uint256 _underlyingQTY, 
        uint256 _priceEn, 
        uint256 _underlyingValueEn, 
        uint256 _capPoolU, 
        uint256 _usrMarginU,
        uint256 _feeU,
        uint256 _capU,
        uint256 _usrPoolQ
        );

    function initialize(
        address _token0, uint8 _lever, uint8 _direction,
        address _leverage, uint256 _purcRateEn, uint256 _redeeRateEn, uint256 _manaRateEn,
        address _addrBase, uint256 _liquDiscountRateEn, uint256 _ownerRateEn, address _pair
        ) external;

    function updateParameter(
        uint256 _purcRateEn, uint256 _redeeRateEn, uint256 _manaRateEn, uint256 _liquDiscountRateEn, 
        uint256 _ownerRateEn, address exchangeAddr0, address exchangeAddr1
        )external;
    function closeForced()external returns(uint8 );
    function mint(address to)external returns(uint256 liquidity);
    function purchase(address to)external returns(uint256 amtLever);
    function redeem(address to)external returns(uint256 amtAsset, uint256 amtU);
    function recycle(address to)external returns(uint256 amtTokenA, uint256 amtU);
    function liquidation3Part(address to)external returns(uint256 amtTokenA);
    function liquidationLPT(address to)external returns(uint256 amtTokenA, uint256 amtU);
    function cake(bool isTransfer)external returns(uint256 amtU);
    function _updateIndexes() external;//local
    function liquidationLT(address to)external returns(uint256 amtU);
}
