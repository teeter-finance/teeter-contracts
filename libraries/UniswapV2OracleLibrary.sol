pragma solidity ^0.5.6;

import '../interfaces/IUniswapV2Pair.sol';
import "../interfaces/IERC20.sol";
import "./SafeMath.sol";

// library with helper methods for oracles that are concerned with computing average prices
library UniswapV2OracleLibrary {
    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(
        address pair
    ) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp = uint32(block.timestamp % 2 ** 32);
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        uint8 deciToken0 = IERC20(IUniswapV2Pair(pair).token0()).decimals();
        uint8 deciToken1 = IERC20(IUniswapV2Pair(pair).token1()).decimals();
        reserve0 = uint112(SafeMath.div(
            SafeMath.mul(uint256(reserve0), 1000000000000000000), 
            (uint256(10)**deciToken0)
        ));
        reserve1 = uint112(SafeMath.div(
            SafeMath.mul(uint256(reserve1), 1000000000000000000), 
            (uint256(10)**deciToken1)
        ));
        
        if (blockTimestamp > blockTimestampLast) {
            uint32 timeElapsed = uint32(SafeMath.sub(blockTimestamp, blockTimestampLast));
            require((reserve0 > 0) && (reserve1 > 0), "DIV_BY_ZERO");
            price0Cumulative += SafeMath.div(
                SafeMath.mul(
                    (uint(reserve1)<<112), 
                    timeElapsed
                ), 
                reserve0
            );
            price1Cumulative += SafeMath.div(
                SafeMath.mul(
                    (uint(reserve0)<<112), 
                    timeElapsed
                ),
                reserve1
            );
        }
    }
}
