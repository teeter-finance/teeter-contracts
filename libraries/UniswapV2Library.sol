pragma solidity >=0.5.0;

import '../interfaces/IUniswapV2Pair.sol';
import "./SafeMath.sol";
//import "./Math.sol";

library UniswapV2Library {
    //using Math for uint;

    // fetches and sorts the reserves for a pair
    function getReserves(address tokenA, address tokenB, address _pair) internal view returns (uint reserveA, uint reserveB) {
        //(address token0,) = sortTokens(tokenA, tokenB);
        (address token0,) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(_pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        //require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        //require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        //uint amountInWithFee = amountIn.mul(997);
        uint amountInWithFee = SafeMath.mul(amountIn, 997);
        //uint numerator = amountInWithFee.mul(reserveOut);
        uint numerator = SafeMath.mul(amountInWithFee, reserveOut);
        //uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        uint denominator = SafeMath.add(SafeMath.mul(reserveIn, 1000), amountInWithFee);
        //require(denominator>0, "denominator err");
        amountOut = SafeMath.div(numerator, denominator);
    }

    //xuj performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(uint amountIn, address[] memory path, address _pair) internal view returns (uint[] memory amounts) {
        //require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](2);
        amounts[0] = amountIn;
        (uint reserveIn, uint reserveOut) = getReserves(path[0], path[1], _pair);
        amounts[1] = getAmountOut(amounts[0], reserveIn, reserveOut);
    }


}
