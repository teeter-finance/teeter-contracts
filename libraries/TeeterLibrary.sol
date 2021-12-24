pragma solidity ^0.5.6;

import "../interfaces/IERC20.sol";
import '../interfaces/IUniswapV2Pair.sol';
import '../libraries/UniswapV2OracleLibrary.sol';
import './UniswapV2Library.sol';
import "./SafeMath.sol";

library TeeterLibrary {

    function getUNIPriceEn(address quote, address pairAddr) internal view returns (uint priceEn){
        if(pairAddr == address(0x0)){return 0;}
        IUniswapV2Pair uniV2Pair = IUniswapV2Pair(pairAddr);
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(pairAddr);
        (uint256 reserve0, uint256 reserve1, uint32 blockTimestampLast) = uniV2Pair.getReserves();
        {
            if(reserve0 == 0 || reserve1 == 0){ return 0;}
            //require(blockTimestamp > blockTimestampLast, "blockTimestampLast err");
            uint32 timeElapsed = uint32(SafeMath.sub(blockTimestamp, blockTimestampLast)); 
            if (quote == uniV2Pair.token0()) {
                priceEn = SafeMath.div((SafeMath.sub(price0Cumulative, uniV2Pair.price0CumulativeLast())), timeElapsed);//check in line19
            } else {
                priceEn =SafeMath.div((SafeMath.sub(price1Cumulative, uniV2Pair.price1CumulativeLast())), timeElapsed);//check in line19
            }            
        }
        
    }

    //get the quote/DAI price in uniswap by Cumulative
    function getLastPriceEn(address quote, address[] memory pairAddrs) internal view returns (uint priceEn){
        uint perPriceEn;
        uint8 j = 0;
        for(uint8 i=0; i<pairAddrs.length; i++){
            perPriceEn = getUNIPriceEn(quote, pairAddrs[i]);
            if(perPriceEn>0){
                priceEn += perPriceEn;
                j += 1;
            }
        }
        if(j==0){return 0;}
        priceEn = priceEn/j;//j!=0 judged before
    }    

    function convertTo18(address token, uint256 amtToken) internal view returns (uint amtCovert){
        uint8 decimals = IERC20(token).decimals();
        //amtCovert = amtToken*1000000000000000000/(uint256(10)**decimals);
        amtCovert = SafeMath.div(
            SafeMath.mul(amtToken, 1000000000000000000), 
            (uint256(10)**decimals)
        );
        
    }

    function convert18ToOri(address token, uint256 amtToken) internal view returns (uint amtCovert){
        uint8 decimals = IERC20(token).decimals();
        //amtCovert = (amtToken*(uint256(10)**decimals))/1000000000000000000;
        amtCovert = SafeMath.div(
            SafeMath.mul(
                amtToken, 
                (uint256(10)**decimals)
            ), 
            1000000000000000000
        );
    }
    


    function swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to,
        address _pair
    ) internal {
        (address input, address output) = (path[0], path[1]);
        (address _token0, ) = input < output ? (input, output) : (output, input);
        uint256 amountOut = amounts[1];
        (uint256 amount0Out, uint256 amount1Out) = input == _token0 ? (uint256(0), amountOut): (amountOut, uint256(0));
        IUniswapV2Pair(_pair).swap(amount0Out, amount1Out, _to, new bytes(0));
    }    

}
