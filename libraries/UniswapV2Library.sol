pragma solidity >=0.5.0;

import '../interfaces/IUniswapV2Pair.sol';
import "./SafeMath.sol";
//import "./Math.sol";

library UniswapV2Library {
    function getReserves(address tokenA, address tokenB, address _pair) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(_pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        uint amountInWithFee = SafeMath.mul(amountIn, 997);
        uint numerator = SafeMath.mul(amountInWithFee, reserveOut);
        uint denominator = SafeMath.add(SafeMath.mul(reserveIn, 1000), amountInWithFee);
        amountOut = SafeMath.div(numerator, denominator);
    }

    function getAmountsOut(uint amountIn, address[] memory path, address _pair) internal view returns (uint[] memory amounts) {
        amounts = new uint[](2);
        amounts[0] = amountIn;
        (uint reserveIn, uint reserveOut) = getReserves(path[0], path[1], _pair);
        amounts[1] = getAmountOut(amounts[0], reserveIn, reserveOut);
    }


}
