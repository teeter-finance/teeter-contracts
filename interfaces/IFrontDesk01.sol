pragma solidity ^0.5.6;

interface IFrontDesk01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function depositTop(
        address token0, uint256 amt, address to, uint256 deadline
        ) external returns(uint256 liquidity);
    function deposit(
        address token0, uint256 amt, address to, uint256 deadline
        ) external returns(uint256 liquidity);
    function purchaseTop(
        uint256 amtTokenIn, address token0, address to, uint256 deadline
        ) external returns (uint256 amtLever);
    function purchase(
        uint256 amtTokenIn, address token0, address to, uint256 deadline
        ) external returns (uint256 amtLever);
    function redeemTop(
        uint256 amtLeverIn, address token0, address to, uint256 deadline
        ) external returns (uint256 amtToken0, uint256 amtU);
    function redeem(
        uint256 amtLeverIn, address token0, address to, uint256 deadline
        ) external returns (uint256 amtToken0, uint256 amtU);
    function recycleTop(
        uint256 amtliquIn, address token0, address to, uint256 deadline
        ) external returns (uint256 amtToken0, uint256 amtU);
    function recycle(
        uint256 amtliquIn, address token0, address to, uint256 deadline
        ) external returns (uint256 amtToken0, uint256 amtU);   
    function liquidation3PartTop(
        uint256 amtUin, address token0, address to, uint256 deadline
        )external returns (uint256 amtToken0);
    function liquidation3Part(
        uint256 amtUin, address token0, address to, uint256 deadline
        )external returns (uint256 amtToken0);
    function liquidationLPTTop(
        uint256 amtLPTin, address token0, address to, uint256 deadline
        )external returns (uint256 amtToken0, uint256 amtU);
    function liquidationLPT(
        uint256 amtLPTin, address token0, address to, uint256 deadline
        )external returns (uint256 amtToken0, uint256 amtU);
}
