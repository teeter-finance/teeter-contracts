pragma solidity =0.5.16;

import "./interfaces/ITeeterUnderlyingTop.sol";
import "./interfaces/ITeeterFactory.sol";
import "./TeeterERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TeeterLibrary.sol";
import "./interfaces/IERC20.sol";
import './interfaces/ITeeterLeverage.sol';
import './libraries/TransferHelper.sol';
//import './libraries/TeeterExchange.sol';

// the init version do not take fee management into consideration
contract TeeterUnderlyingTop is ITeeterUnderlyingTop, TeeterERC20 {
    address[] public exchangeAddrs;
    address public factory; //address of factory
    address public leverage;
    address public token0; //address of quote token
    uint256 public capAddU;//add asset u by capital mint() add, recycle() sub temp may dele
    uint256 public underlyingU;
    uint256 private underlyingQTY;
    uint256 private underlyingValueEn;
    uint256 private fundSoldQTY;
    uint256 private fundSoldValueEn;
    uint256 public price0En;
    uint256 public priceEn;
    uint256 public purcRateEn;//purchase fee rate 
    uint256 public redeeRateEn;//redeem fee rate 
    uint256 public manaRateEn;//management fee rate 
    uint256 public liquDiscountRateEn;//discount rate 
    uint256 public ownerRateEn;//owner management fee rate
    address public addrBase;
    uint256 public balBaseLast;//bal of base in last time
    uint256 private nvEn = 5192296858534827628530496329220096 ;//fixed point adj
    uint8 public initLever;
    uint256 private presLeverEn;//fixed point adj
    uint8 public direction;
    
    uint8 public status = 1;// 1 active; 0 nagative;
    uint private blockTimestampLast;//have value in update function
    uint public blockTimestampInit;
    uint256 private capPoolU;//accrued blone to capital
    uint256 private feeU;//Transaction Fee + Fund management fee
    uint256 private usrMarginU; //the user margin USDT/DAI, user tuansfered in underlying contract for puchase leverage token
    uint256 private capU; //the U belone to cap
    uint256 public refNvEn = 5192296858534827628530496329220096;
    uint256 private usrPoolQ;
    uint256 public ownerU;

    uint256 private unlocked = 1;
    
    constructor() public {
        //msg.sender == factory contract address
        factory = msg.sender;
    }

    modifier lock() {
        require(unlocked == 1, "TeeterUnderlyingTOP: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }


    function initialize(
        address _token0, uint8 _lever, uint8 _direction,
        address _leverage, uint256 _purcRateEn, uint256 _redeeRateEn, uint256 _manaRateEn,
        address _addrBase, uint256 _liquDiscountRateEn, uint256 _ownerRateEn, address _pair
        ) external {
        //the caller must be factory contract
        require(msg.sender == factory, "TeeterUnderlyingTOP: FORBIDDEN");
        token0 = _token0;
        initLever = _lever;
        presLeverEn = uint256(_lever)<<112;//3<<112
        direction = _direction;
        leverage = _leverage;
        purcRateEn = _purcRateEn;
        redeeRateEn = _redeeRateEn;
        manaRateEn = _manaRateEn;
        addrBase = _addrBase;
        liquDiscountRateEn = _liquDiscountRateEn;
        ownerRateEn = _ownerRateEn;
        //symbol =  TeeterLibrary.strMulJoin(IERC20(token0).symbol(), '3L_LP'); // too big
        symbol = 'bTeeter';//FOR TEMP
        //name = symbol; //FOR TEMP
        exchangeAddrs.push(_pair);
        exchangeAddrs.push(address(0x0));
    }

    function updateParameter(
        uint256 _purcRateEn, uint256 _redeeRateEn, uint256 _manaRateEn, uint256 _liquDiscountRateEn, 
        uint256 _ownerRateEn, address exchangeAddr0, address exchangeAddr1
        ) external {
        //the caller must be factory contract
        require(msg.sender == ITeeterFactory(factory).owner(), "TeeterUnderlyingTOP: FORBIDDEN");
        purcRateEn = _purcRateEn;
        redeeRateEn = _redeeRateEn;
        manaRateEn = _manaRateEn;
        liquDiscountRateEn = _liquDiscountRateEn;
        ownerRateEn = _ownerRateEn;
        exchangeAddrs[0] = exchangeAddr0;
        if(exchangeAddr1!=address(0x0)){exchangeAddrs[1] = exchangeAddr1;}
    }        


    function getReserves() public view returns (
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
        uint256 _usrPoolQ){
        _fundSoldValueEn = fundSoldValueEn;
        _fundSoldQTY = fundSoldQTY;
        _nvEn  = nvEn;
        _presLeverEn = presLeverEn;
        _underlyingU = underlyingU;        
        _underlyingQTY = underlyingQTY;
        _priceEn = priceEn;
        _underlyingValueEn = underlyingValueEn;
        _capPoolU = capPoolU;
        _usrMarginU = usrMarginU;
        _feeU = feeU;
        _capU = capU;
        _usrPoolQ = usrPoolQ;
    }

    function updatePrice()public {// kovan for test public
        priceEn = TeeterLibrary.getLastPriceEn(token0, exchangeAddrs); //kovan
    }
    
    function _rebalanceD()private{
        presLeverEn = uint256(initLever)<<112;//3<<112
        refNvEn = nvEn;
        //=M21-L21
        usrMarginU = SafeMath.sub(usrMarginU, capPoolU);

        uint256 underlyingQTYlast = underlyingQTY;
        //underlyingQTY=M24/J24*G24
        underlyingQTY = SafeMath.div(SafeMath.mul(usrMarginU, presLeverEn), priceEn);
        if(underlyingQTY > underlyingQTYlast){return;}//err underqty
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        //swap todo 
        //Q2U deltaUnderlyingQTY
        _swap((underlyingQTYlast-underlyingQTY), token0);//already judged before, so don’t need safeMath here.
        uint256 swapU = SafeMath.sub(
            TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this))), balBaseLast
        );
        balBaseLast += swapU;  
        //end

        //underlyingU=H23+AD24
        underlyingU += swapU;
        capU += capPoolU;
        capPoolU = 0;

    }

    function _rebalanceU() private{
        //presLeverEn = 15576890575604482885591488987660288;//3<<112
        refNvEn = nvEn;
        uint256 swapQ;
        //underlyingUDelta=(M12-L12+P12*J11)*G$2-K11
        //(usrMarginU-capPoolU+usrPoolQ*priceEn)*initLever-underlyingValueEn
        uint256 sub1En = SafeMath.mul(
            (SafeMath.sub(usrMarginU, capPoolU) + (SafeMath.mul(usrPoolQ, priceEn)>>112)), 
            uint256(initLever)<<112
        );
        uint256 underlyingUDelta = SafeMath.sub(sub1En, underlyingValueEn);
        // uint256 underlyingUDelta = SafeMath.sub(
        //     SafeMath.mul((usrMarginU + (SafeMath.mul(usrPoolQ, priceEn)>>112)), (uint256(initLever)<<112)), 
        //     underlyingValueEn
        // )>>112;
        // underlyingU=IF(
        //     H33>((M34-L34+P34*J33)*G$2-K33),
        //     H33-((M34-L34+P34*J33)*G$2-K33),
        //     0)
        if(underlyingU > underlyingUDelta){
            underlyingU -= underlyingUDelta;//already judged before, so don’t need safeMath here.
        }else{
            underlyingUDelta = underlyingU;
            underlyingU = 0;
        }
        //swap U2Q
        _swap(underlyingUDelta, addrBase);
        swapQ = SafeMath.sub(
            TeeterLibrary.convertTo18(token0, IERC20(token0).balanceOf(address(this))), underlyingQTY
        );
        balBaseLast = SafeMath.sub(balBaseLast, underlyingUDelta);
        //swap end

        //underlyingQTY=I33+AF34
        underlyingQTY += swapQ;
        //underlyingValueEn=I34*J34
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        //presLeverEn=K34/B34
        presLeverEn = SafeMath.div(underlyingValueEn, fundSoldValueEn>>112);
        capU += capPoolU;
        capPoolU = 0;
    }
    

    /**
     *  from front and the value will has been expanded 2**112
     * @dev create fund or add assets to fund. xxEn should be sure has been expanded 2**112
     */
    function _updateIndexes() public{//local, kovan be private
        require(fundSoldQTY >0 || underlyingU>0,"TeeterUnderlyingTOP: EMPTY");
        if(price0En==priceEn || fundSoldValueEn==0){return;}
        //status > 0 means fund open
        if(status == 1){
            uint timeElapsed = SafeMath.sub(block.timestamp, blockTimestampLast); // current time must more than last time. not need SafeMath
            uint daysEn = SafeMath.div((timeElapsed)<<112, 86400);//86400 one day secs
            //fee =N2+M2*$G$44
            uint256 feeLast = feeU;
            feeU += (
                SafeMath.mul(
                    usrMarginU, 
                    SafeMath.mul(manaRateEn, daysEn)>>112
                )>>112
            );
            //underlyingValueEn =I5*H5
            uint256 _underlyingValueLastEn = underlyingValueEn;
            underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
            //=IF((B2+(K3-K2)-(N3-N2))>0,B2+(K3-K2)-(N3-N2),0)
            if(priceEn > price0En){
                fundSoldValueEn += SafeMath.sub(underlyingValueEn, _underlyingValueLastEn) ;
            }else{
                fundSoldValueEn = SafeMath.sub(fundSoldValueEn, SafeMath.sub(_underlyingValueLastEn, underlyingValueEn));
            }
            fundSoldValueEn = SafeMath.sub(fundSoldValueEn, (SafeMath.sub(feeU, feeLast))<<112);
            //fund close
            if(fundSoldValueEn>underlyingValueEn){
                status = 0;
                //profit distribution
                //=O13+N13*(1-$W$44) //cake
                //ownerU += feeU*(1-ownerRateEn)
                ownerU += (SafeMath.mul(
                    feeU, 
                    SafeMath.sub(5192296858534827628530496329220096, ownerRateEn))>>112
                );
                //capU = balBaseLast - ownerU - underlyingU;
                capU = SafeMath.sub(balBaseLast, (ownerU + underlyingU));
                feeU = 0;
                //profit distribution end
                fundSoldValueEn = 0;
                fundSoldQTY = 0;
                nvEn = 0;
                presLeverEn = 0;
                usrMarginU = 0;
                usrPoolQ = 0;
                capPoolU = 0;
                price0En = priceEn;
            }else{
                //nvEn ==IF(D3>0,B3/D3,$F$2)
                if(fundSoldQTY!=0){
                    //B5/D5
                    nvEn = SafeMath.div(fundSoldValueEn, fundSoldQTY);
                    presLeverEn = SafeMath.div(underlyingValueEn, fundSoldValueEn>>112);                         
                }
                //=M2-(N3-N2)
                //usrMarginU=usrMarginU-(feeU-feeLast)
                usrMarginU =SafeMath.sub(usrMarginU, (feeU-feeLast));//feeU been added in line 214, so feeU > feeLast. here not need safeMath for feeU
                //=IF((B3-M3)>=0,0,M3-B3)
                //=IF((fundSoldValueEn-usrMarginU)>=0,0,usrMarginU-fundSoldValueEn)
                uint256 fundSoldValue = fundSoldValueEn>>112;
                if(fundSoldValue >= usrMarginU){
                    capPoolU = 0;
                }else{
                    capPoolU = usrMarginU - fundSoldValue;//already judged before, so don’t need safeMath here.
                }
                //=IF((B3-M3)>=0,(B3-M3)/J3,0)
                //usrPoolQ=IF((fundSoldValueEn-usrMarginU)>=0,(fundSoldValueEn-usrMarginU)/priceEn,0)
                if(fundSoldValue >= usrMarginU){
                    usrPoolQ = SafeMath.div( ((fundSoldValue-usrMarginU)<<112), priceEn);//already judged before, so don’t need safeMath here.
                }else{
                    usrPoolQ = 0;
                }
                price0En = priceEn;
                if(SafeMath.mul(5, nvEn) <= refNvEn){ _rebalanceD(); }else if(SafeMath.div(nvEn, 3) >= refNvEn){_rebalanceU();}//check swap
            }
        }else{
            price0En = priceEn;
            underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        }
        blockTimestampLast = block.timestamp;
    }

    /**
     *  from front and the value will be expand 2*112
     * @param to address send to
     * @dev create fund or add assets to fund
     */
    function mint(address to) external lock returns(uint256 liquidity){
        require(status == 1, "TeeterUnderlyingTOP: FUNDCLOSE");
        //get bal of user added base curr
        uint256 baseBal = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        //calculate the amount of cap sent
        uint256 baseAmt = SafeMath.sub(baseBal, balBaseLast);
        capAddU += baseAmt;//check it is need
        require((baseAmt > 10000000), "TeeterUnderlyingTOP: INSUFFICIENT_baseBal");//min is 10000000, the unit not sure 
        updatePrice();
        if(totalSupply == 0){
            //require(status > 0, "TeeterUnderlyingTOP: FUNDCLOSE");
            require(priceEn!=0, "TEETER_PRICEIS0");
            //require((capPoolU + feeU + usrMarginU +usrPoolQ)==0, "TeeterUnderlyingTOP: HASFEE");
            nvEn = 5192296858534827628530496329220096;
            presLeverEn =15576890575604482885591488987660288;//3<<112
            //=H2
            liquidity = baseAmt;// amount of LPT
            underlyingU = baseAmt;
            blockTimestampLast = block.timestamp;
            blockTimestampInit = block.timestamp;
            price0En = priceEn;
        }else{
            _updateIndexes();
            if(status != 1){TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, baseAmt)); return 0;}//if close return baseCurr user added
            //=T4*SUM(W$2:W3)/(K3+L3+N3*(1-$W$44)+O3+H3-P3*J4)
            //liquidity = baseAmt*totalSupply/(underlyingValueEn+capPoolU+feeU*(1-ownerRateEn)+capU+underlyingU-usrPoolQ*priceEn)
            //uint256 feeUCaked = (feeU*(5192296858534827628530496329220096-ownerRateEn))>>112;
            uint256 feeUCaked = SafeMath.mul(feeU, SafeMath.sub(5192296858534827628530496329220096, ownerRateEn))>>112;
            uint256 numerator = SafeMath.mul(baseAmt, totalSupply);
            uint256 sub1 = (underlyingValueEn>>112) + capPoolU + feeUCaked + capU + underlyingU;
            uint256 sub2 = SafeMath.mul(usrPoolQ, priceEn)>>112;
            uint256 denominator = SafeMath.sub(sub1, sub2);
            liquidity = SafeMath.div(numerator, denominator);
            require(liquidity !=0, 'TeeterUnderlying:LPTERR');
            underlyingU += baseAmt;
        }
        //update balBaseLast
        balBaseLast = baseBal;
        _mint(to, liquidity); //add LPT to capital user
    }
    

    //if transfer base to underlying and exceed avai again procees revert. the token transfered before not be return until asset be add.
    function purchase(address to) external lock returns(uint256 amtLever){
        require(status == 1, "TeeterUnderlyingTOP: FUNDCLOSE");
        updatePrice();
        uint256 balanceBase = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        require(balanceBase != 0, "TeeterUnderlyingTOP: balanceBaseIS0");
        uint256 amtTokenIn = SafeMath.sub(balanceBase, balBaseLast);
        require((amtTokenIn > 10000000000000000000), "TeeterUnderlyingTOP: INSUFFICIENT_AMTTOKENIN");//min is 10U
        _updateIndexes();
        if(status != 1){TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtTokenIn)); return 0;}//if close return token0

        //Maximum purchase amount H5/G6 underlyingU/presLeverEn
        uint256 amtMaxPurc = SafeMath.div(underlyingU<<112, presLeverEn);
        //return base token exceed max to user
        if(amtTokenIn > amtMaxPurc){
            uint256 amtTokenInReturn = TeeterLibrary.convert18ToOri(addrBase, SafeMath.sub(amtTokenIn, amtMaxPurc));
            TransferHelper.safeTransfer(addrBase, to, amtTokenInReturn);
            balanceBase -= (amtTokenIn - amtMaxPurc); //already judged in line338 and line346, so don’t need safeMath here.
            amtTokenIn = amtMaxPurc;
        }
        //feeU =N5+R6*$C$44 
        uint256 feeUDelta = SafeMath.mul(amtTokenIn, purcRateEn)>>112;
        feeU += feeUDelta;
        //=H5-(R6-(N6-N5))*G6
        //underlyingU=underlyingU-(amtTokenIn-(feeU-feeULast))*presLeverEn
        uint256 amtTokenInFeed = SafeMath.sub(amtTokenIn, feeUDelta);
        //uint256 deltaUnderlyingU = (amtTokenInFeed * presLeverEn)>>112;
        uint256 deltaUnderlyingU = SafeMath.mul(amtTokenInFeed, presLeverEn)>>112;
        //underlyingU -= deltaUnderlyingU;
        underlyingU = SafeMath.sub(underlyingU, deltaUnderlyingU) ;
        //swap U2Q todo 
        _swap(deltaUnderlyingU, addrBase);//check need qty of got, may optimized
        uint256 deltaUnderlyingQTY = SafeMath.sub(
            TeeterLibrary.convertTo18(token0, IERC20(token0).balanceOf(address(this))), underlyingQTY
        );        
        //end
        //=((R6-(N6-N5))*G6/AE6)+I5
        //underlyingQTY=((amtTokenIn-(feeU-feeULast))*presLeverEn/exePriceEn)+underlyingQTY
        //underlyingQTY += SafeMath.div(amtTokenInFeed*presLeverEn, exePriceEn<<112); //excel ori
        underlyingQTY += deltaUnderlyingQTY;
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        //=IF(((R6-(N6-N5))*G6>(I6-I5)*J6),M5+(R6-(N6-N5))-((R6-(N6-N5))*G6-(I6-I5)*J6),M5+(R6-(N6-N5)))
        //usrMarginU=IF(
            //((amtTokenIn-(feeU-feeULast))*presLeverEn>(underlyingQTY-underlyingQTYLast)*priceEn),
            //usrMarginU+(amtTokenIn-(feeU-feeULast))-((amtTokenIn-(feeU-feeULast))*presLeverEn-(underlyingQTY-underlyingQTYLast)*priceEn),
            //usrMarginU+(amtTokenIn-(feeU-feeULast))
        //)
        uint256 amtTokenInFeedLeveEn = deltaUnderlyingU<<112;
        //uint256 deltaUnderlyingQTYValueEn = deltaUnderlyingQTY * priceEn;
        uint256 deltaUnderlyingQTYValueEn = SafeMath.mul(deltaUnderlyingQTY, priceEn);
        if(amtTokenInFeedLeveEn > deltaUnderlyingQTYValueEn){
            usrMarginU += SafeMath.sub(
                amtTokenInFeed, 
                SafeMath.sub(
                    amtTokenInFeedLeveEn, deltaUnderlyingQTYValueEn
                )>>112
            );
        }else{
            usrMarginU += amtTokenInFeed;
        }
        //=IF(((R6-(N6-N5))*G6>(I6-I5)*J6),O5+((R6-(N6-N5))*G6-(I6-I5)*J6),O5)
        //capU=IF(
            //((amtTokenIn-(feeU-feeULast))*presLeverEn>(underlyingQTY-underlyingQTYLast)*presLeverEn),
            //capU+((amtTokenIn-(feeU-feeULast))*presLeverEn-(underlyingQTY-underlyingQTYLast)*presLeverEn),
            //capU
        //)
        if(amtTokenInFeedLeveEn > deltaUnderlyingQTYValueEn){
            capU += ((amtTokenInFeedLeveEn - deltaUnderlyingQTYValueEn)>>112);//already judged before, so don’t need safeMath here.
        }
        //=IF(H6>0,(R6-(N6-N5)-((R6-(N6-N5))*G6-(I6-I5)*J6))/F6,0)
        //amtLever=IF(underlyingU>0,(amtTokenIn-(feeU-feeULast)-((amtTokenIn-(feeU-feeULast))*presLeverEn-(underlyingQTY-underlyingQTYLast)*priceEn))/nvEn,0)
        //amtLever = (amtTokenInFeed - (amtTokenInFeedLeveEn-deltaUnderlyingQTYValueEn))/nvEn
        amtLever = SafeMath.div(
            SafeMath.sub(
                amtTokenInFeed<<112, 
                SafeMath.sub(amtTokenInFeedLeveEn, deltaUnderlyingQTYValueEn)
            ), 
            nvEn
        );
        //=D5+V6 fundSoldQTY+amtLever
        fundSoldQTY += amtLever;
        fundSoldValueEn = SafeMath.mul(fundSoldQTY, nvEn);
        //balBaseLast = balBaseLast + amtTokenIn - deltaUnderlyingU;//the price of Q maybe change, need to check
        balBaseLast = SafeMath.sub(SafeMath.add(balBaseLast, amtTokenIn), deltaUnderlyingU);//the price of Q maybe change, need to check
        //mint the leverage token and transfer to user
        ITeeterLeverage(leverage).mint(to, amtLever);
        //mint end
    }
    
    uint256 public exePrice;//for test
    function _swap(uint256 _amt, address _path0) private {
        address[] memory path = new address[](2);
        if(_path0 == addrBase){
            path[0] = addrBase;
            path[1] = token0;
        }else{
            path[1] = addrBase;
            path[0] = token0;             
        }
        uint256 amt = TeeterLibrary.convert18ToOri(path[0], _amt);
        uint256[] memory amounts0;
        uint256[] memory amounts1;
        if(exchangeAddrs[1]!=address(0x0)){
            amounts0 = UniswapV2Library.getAmountsOut(amt/2, path, exchangeAddrs[0]);
            amounts1 = UniswapV2Library.getAmountsOut(SafeMath.sub(amt, amounts0[0]), path, exchangeAddrs[1]);
        }else{
            amounts0 = UniswapV2Library.getAmountsOut(amt, path, exchangeAddrs[0]);
            amounts1 = new uint256[](2);
        }
        if(amounts0[0]>0){
            TransferHelper.safeTransfer(path[0], exchangeAddrs[0], amounts0[0]);
            TeeterLibrary.swap(amounts0, path, address(this), exchangeAddrs[0]);
        }
        if(amounts1[0]>0){
            TransferHelper.safeTransfer(path[0], exchangeAddrs[1], amounts1[0]);
            TeeterLibrary.swap(amounts1, path, address(this), exchangeAddrs[1]);
        }        
        // uint256[] memory amounts0 = UniswapV2Library.getAmountsOut(amt/2, path, exchangeAddrs[0]);
        // uint256[] memory amounts1 = new uint256[](2);
        // if(exchangeAddrs[1]!=address(0x0)){
        //     amounts1 = UniswapV2Library.getAmountsOut(amt/2, path, exchangeAddrs[1]);
        // }
        // require(amounts0[1]>0 || amounts1[1]>0, "TeeterUnderlyingTOP: CANNOTSWAP");
        // if(amounts0[1]>0 && amounts1[1]>0){
        //     amounts0[0] = amt/2;
        //     amounts1[0] = amt - amounts0[0];
        // }else if(amounts0[1]>0 && amounts1[1]==0){
        //     amounts0[0] = amt;
        //     amounts1[0] = 0;
        //     amounts0 = UniswapV2Library.getAmountsOut(amt, path, exchangeAddrs[0]);
        // }else if(amounts0[1]==0 && amounts1[1]>0){
        //     amounts0[0] = 0;
        //     amounts1[0] = amt;
        //     amounts1 = UniswapV2Library.getAmountsOut(amt, path, exchangeAddrs[1]);
        // }
        // if(amounts0[0]>0){
        //     TransferHelper.safeTransfer(path[0], exchangeAddrs[0], amounts0[0]);
        //     TeeterLibrary.swap(amounts0, path, address(this), exchangeAddrs[0]);
        // }
        // if(amounts1[0]>0){
        //     TransferHelper.safeTransfer(path[0], exchangeAddrs[1], amounts1[0]);
        //     TeeterLibrary.swap(amounts1, path, address(this), exchangeAddrs[1]);
        // }

        //for test
        if(_path0 == addrBase){
            //exePrice = TeeterLibrary.convertTo18(path[0], amounts[0])/TeeterLibrary.convertTo18(path[1], amounts[1]);
            exePrice = SafeMath.div(TeeterLibrary.convertTo18(path[0], amounts0[0]), TeeterLibrary.convertTo18(path[1], amounts0[1]));
        }else{
            //exePrice = TeeterLibrary.convertTo18(path[1], amounts[1])/TeeterLibrary.convertTo18(path[0], amounts[0]);
            exePrice = SafeMath.div(TeeterLibrary.convertTo18(path[1], amounts0[1]), TeeterLibrary.convertTo18(path[0], amounts0[0]));
        }
        //for test end
    }
    //user transfer leverage token to underlying contract for asset token return
    function redeem(address to) external lock returns(uint256 amtAsset, uint256 amtU){
        require(status == 1, "TeeterUnderlyingTOP: FUNDCLOSE");
        //require(fundSoldQTY>0, "TeeterUnderlyingTOP: FUNDQTYERR");//del temp
        updatePrice();
        uint256 amtLeverTokenIn = IERC20(leverage).balanceOf(address(this));
        require(amtLeverTokenIn !=0, "TeeterUnderlyingTOP: INSUFFICIENT_amtLeverTokenIn");
        _updateIndexes();
        if(status != 1){TransferHelper.safeTransfer(leverage, to, amtLeverTokenIn); return (0, 0);}//if close return token0

        //=N15+S16*F16*$E$44 feeU = amtLeverTokenIn*nvEn*redeeRateEn
        uint256 feeUDelta = 
            SafeMath.mul(
                SafeMath.mul(amtLeverTokenIn, nvEn)>>112, 
                redeeRateEn
            )>>112;
        feeU += feeUDelta;
        //=IF(R14,L13*R14/((SUM(T$2:T13)-SUM(R$2:R13)))-(M14-M13),0)
        uint256 leverTotalSupply = IERC20(leverage).totalSupply();
        uint256 swapU;
        //uint256 amtLeverTokenInValue = (amtLeverTokenIn*priceEn)>>112;
        uint256 amtLeverTokenInValue = SafeMath.mul(amtLeverTokenIn, priceEn)>>112;
        //=H15+(I15-P15)*S16/(SUM($V$2:V15)-SUM($S$2:S15))*J16
        //underlyingU = underlyingU + SafeMath.div(amtLeverTokenInValue*(underlyingQTY-usrPoolQ), leverTotalSupply);
        underlyingU = underlyingU + SafeMath.div(SafeMath.mul(amtLeverTokenInValue, SafeMath.sub(underlyingQTY, usrPoolQ)), leverTotalSupply);
        //underlyingU=underlyingU+(underlyingQTYlast-usrPoolQ)*amtLeverTokenIn*priceEn/leverTotalSupply
        //underlyingU += SafeMath.div( ((underlyingQTY-usrPoolQ)*amtLeverTokenIn*priceEn)>>112, leverTotalSupply);
        
        //=I15*(1-S16/(SUM($V$2:V15)-SUM($S$2:S15))) underlyingQTY*(1-amtLeverTokenIn/leverTotalSupply) underlyingQTY-underlyingQTY*amtLeverTokenIn/leverTotalSupply
        uint256 underlyingQTYlast = underlyingQTY;
        // underlyingQTY -= SafeMath.div(
        //     SafeMath.mul(underlyingQTY, amtLeverTokenIn), leverTotalSupply
        // ); 
        underlyingQTY = SafeMath.sub(
            underlyingQTY, 
            SafeMath.div(
                SafeMath.mul(underlyingQTY, amtLeverTokenIn), leverTotalSupply
            )
        ); 

        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);

        //swap todo
        _swap((underlyingQTYlast-underlyingQTY), token0);// underlyingQTY has been subed, so not need SafeMath here 
        //=AE16*(I15-I16)
        swapU = SafeMath.sub(
            TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this))), balBaseLast
        );
        //swap end
        
        //=IF(S16,(M15-L15)*S16/((SUM(V$2:V15)-SUM(S$2:S15)))-(N16-N15)+(P15*S16/(SUM($V$2:V15)-SUM($S$2:S15))*J16)-(J15*I15*S16/(SUM($V$2:V15)-SUM($S$2:S15))-AD16),0)
        //amtU=IF(
            //amtLeverTokenIn,
            //(usrMarginU-capPoolU)*amtLeverTokenIn/((SUM(V$2:V15)-SUM(S$2:S15)))-(feeU-feeULast)+(usrPoolQ*amtLeverTokenIn/(SUM($V$2:V15)-SUM($S$2:S15))*priceEn)+(AD16-priceEn*underlyingQTY*amtLeverTokenIn/(SUM($V$2:V15)-SUM($S$2:S15))),
            //0
        //)
        {
        //uint256 sum1 = SafeMath.div((SafeMath.sub(usrMarginU, capPoolU) * amtLeverTokenIn), leverTotalSupply) - feeUDelta;
        uint256 sum1 = SafeMath.sub(
            SafeMath.div(
                SafeMath.mul(SafeMath.sub(usrMarginU, capPoolU), amtLeverTokenIn), leverTotalSupply
            ), feeUDelta);
        //uint256 sum2 = SafeMath.div(amtLeverTokenInValue*usrPoolQ, leverTotalSupply); 
        uint256 sum2 = SafeMath.div(SafeMath.mul(amtLeverTokenInValue, usrPoolQ), leverTotalSupply); 
        //uint256 sum3 = SafeMath.div(amtLeverTokenInValue*underlyingQTYlast, leverTotalSupply);
        uint256 sum3 = SafeMath.div(SafeMath.mul(amtLeverTokenInValue, underlyingQTYlast), leverTotalSupply);
        require((sum1 + sum2) > SafeMath.sub(sum3, swapU), "TeeterUnderlyingTOP:INSUFFICIENT AMOUNT U");
        amtU = sum1 + sum2 - SafeMath.sub(sum3, swapU);//has been judged before not need SafeMath
        }

        //=IF((SUM(V$2:V15)-SUM(S$2:S15))>0,(M15)-S16/(SUM(V$2:V15)-SUM(S$2:S15))*(M15),0)
        //usrMarginU = usrMarginU-amtLeverTokenIn*usrMarginU/leverTotalSupply
        uint256 sub2 = SafeMath.div(SafeMath.mul(amtLeverTokenIn, usrMarginU), leverTotalSupply);
        usrMarginU = SafeMath.sub(usrMarginU, sub2);

        //=O15+IF((SUM(V$2:V15)-SUM(S$2:S15)),L15*S16/(SUM(V$2:V15)-SUM(S$2:S15)),0)
        //capU += SafeMath.div(SafeMath.mul(capPoolU, amtLeverTokenIn), leverTotalSupply);
        capU = SafeMath.add(capU, SafeMath.div(SafeMath.mul(capPoolU, amtLeverTokenIn), leverTotalSupply));
        
        //=L15*(1-S16/(SUM(V$2:V15)-SUM(S$2:S15)))
        //capPoolU=capPoolU-capPoolU*amtLeverTokenIn/leverTotalSupply
        //capPoolU -= SafeMath.div(capPoolU*amtLeverTokenIn, leverTotalSupply);
        capPoolU = SafeMath.sub(
            capPoolU, 
            SafeMath.div(SafeMath.mul(capPoolU, amtLeverTokenIn), leverTotalSupply)
        );

        //=P15*(1-S16/((SUM(V$2:V15)-SUM(S$2:S15))))
        //usrPoolQ=usrPoolQ-usrPoolQ*amtLeverTokenIn/leverTotalSupply
        //usrPoolQ -= SafeMath.div(usrPoolQ*amtLeverTokenIn, leverTotalSupply); 
        usrPoolQ = SafeMath.sub(usrPoolQ, SafeMath.div(SafeMath.mul(usrPoolQ, amtLeverTokenIn), leverTotalSupply)); 

        //=D13-R14
        //fundSoldQTY -= amtLeverTokenIn;
        fundSoldQTY = SafeMath.sub(fundSoldQTY, amtLeverTokenIn);
        //=D14*F14
        fundSoldValueEn = SafeMath.mul(fundSoldQTY, nvEn);

        //burn leverage token
        ITeeterLeverage(leverage).burn(address(this), amtLeverTokenIn);
        //return U to user
        if(amtU != 0){
            balBaseLast = SafeMath.sub(SafeMath.add(balBaseLast, swapU), amtU);//update bal of base
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU)); 
        }

    }

    function recycle(address to) external lock returns(uint256 amtToken0, uint256 amtU){
        require(status == 1, "TeeterUnderlyingTOP: FUNDCLOSE");
        updatePrice();
        uint256 amtLPT = this.balanceOf(address(this));
        require((amtLPT>0), "TeeterUnderlyingTOP: BALANCEERR");
        _updateIndexes();
        if(status != 1){TransferHelper.safeTransfer(address(this), to, amtLPT); return (0, 0);}//if close return token0 don't revert
        //amtMaxRecy=(SUM(W$2:W17)-SUM(AA$2:AA17))*(H17+O17+N17*(1-$W$48))/(H17+(I17-P17)*J17+L17+O17+N17*(1-$W$48))
        //amtMaxRecy=totalSupply*(underlyingU+capU+feeU*(5192296858534827628530496329220096-ownerRateEn))/(underlyingU+(underlyingQTY-usrPoolQ)*priceEn+capPoolU+capU+feeU*(5192296858534827628530496329220096-ownerRateEn))
        //H17+O17+N17*(1-$W$48)
        //uint256 hon = underlyingU + capU + ((feeU*(5192296858534827628530496329220096-ownerRateEn))>>112);
        uint256 hon = underlyingU + capU + (SafeMath.mul(feeU, SafeMath.sub(5192296858534827628530496329220096, ownerRateEn))>>112);
        //((I17-P17)*J17+L17)
        //uint256 ipjl = (((underlyingQTY-usrPoolQ)*priceEn)>>112) + capPoolU;
        uint256 ipjl = (SafeMath.mul(SafeMath.sub(underlyingQTY, usrPoolQ), priceEn)>>112) + capPoolU;
        uint256 poolValue = hon + ipjl;
        //uint256 amtMaxRecy = SafeMath.div(totalSupply*hon, poolValue);
        uint256 amtMaxRecy = SafeMath.div(SafeMath.mul(totalSupply, hon), poolValue);
        if(amtLPT > amtMaxRecy){
            uint256 amtLPTReturn;
            amtLPTReturn = amtLPT - amtMaxRecy;//has judged before
            TransferHelper.safeTransfer(address(this), to, amtLPTReturn);
            amtLPT = amtMaxRecy;
        }
        //amtU=AG18/(SUM(W$2:W17)-SUM(AA$2:AA17))*(H17+(I17-P17)*J17+L17+O17+N17*(1-$W$48))
        //AA10/totalSupply*(underlyingU+(underlyingQTY-usrPoolQ)*priceEn+capPoolU+capU+feeU*(5192296858534827628530496329220096-ownerRateEn))
        //amtU = (amtLPT*poolValue)/totalSupply;
        amtU = SafeMath.div(SafeMath.mul(amtLPT, poolValue), totalSupply);

        //=IF(
            //(SUM(W$2:W17)-SUM(AA$2:AA17)),
            //AC17+N17*$W$44*AA18/(SUM(W$2:W17)-SUM(AA$2:AA17)),
        //0)
        //ownerU += SafeMath.div(((ownerRateEn*amtLPT)>>112)*feeU, totalSupply);
        ownerU += SafeMath.div(SafeMath.mul(SafeMath.mul(ownerRateEn, amtLPT)>>112, feeU), totalSupply);

        //capU=O17-X18*O17/(H17+O17+N17*(1-$W$48))
        //capU -= SafeMath.div(amtU*capU, hon);
        capU = SafeMath.sub(
            capU, 
            SafeMath.div(SafeMath.mul(amtU, capU), hon)
        );

        //=N17-(N17*(AA18/(SUM(W$2:W17)-SUM(AA$2:AA17))))
        //feeU=feeU-(feeU*amtLPT/totalSupply)
        //uint256 feeUDelta = SafeMath.div(feeU*amtLPT, totalSupply);
        feeU -= SafeMath.div(SafeMath.mul(feeU, amtLPT), totalSupply);//feeU > feeU*amtLPT/totalSupply, amtLPT<totalSupply not need SafeMath

        //underlyingU=H17-X18*H17/(H17+O17+N17*(1-$W$48))
        //underlyingU -= SafeMath.div(amtU*underlyingU, hon);
        underlyingU = SafeMath.sub(underlyingU, SafeMath.div(SafeMath.mul(amtU, underlyingU), hon));

        //burn liq token
        _burn(address(this), amtLPT); 
        if(amtU != 0){
            balBaseLast = SafeMath.sub(balBaseLast, amtU);//update bal of base
            //capAddU -= amtU;
            capAddU = SafeMath.sub(capAddU, amtU);
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU));
        }

    }

    function liquidation3Part(address to)external lock returns(uint256 amtToken0){
        require(status == 0, "TeeterUnderlyingTOP: FUNDOPEN");
        updatePrice();
        _updateIndexes();
        uint256 amtMaxLiqu = SafeMath.mul(underlyingValueEn>>112, liquDiscountRateEn)>>112;
        uint256 balanceBase = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        uint256 amtTokenIn = SafeMath.sub(balanceBase, balBaseLast);
        require(amtTokenIn > 0, "TeeterUnderlyingTOP: INSUFFICIENT U INPUT");//NO mix limit
        if(amtTokenIn > amtMaxLiqu){
            uint256 amtTokenInReturn = amtTokenIn - amtMaxLiqu;
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtTokenInReturn));
            balanceBase = SafeMath.sub(balanceBase, amtTokenInReturn); 
            amtTokenIn = amtMaxLiqu;
        }
        //=AB40/$U$47/J40 amtToken0 = amtTokenIn/liquDiscountRateEn/priceEn;
        amtToken0 = SafeMath.div(
            SafeMath.div(amtTokenIn<<112, liquDiscountRateEn)<<112, 
            priceEn
        );
        //underlyingQTY -= amtToken0;
        underlyingQTY = SafeMath.sub(underlyingQTY, amtToken0);
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        balBaseLast = balanceBase;//update bal of base
        capU += amtTokenIn;
        //return asset of pool to the 3rd Part
        if(amtToken0 !=0){
            TransferHelper.safeTransfer(token0, to, TeeterLibrary.convert18ToOri(token0, amtToken0));
        }

    }

    function liquidationLPT(address to)external lock returns(uint256 amtToken0, uint256 amtU){
        require((status == 0 || status == 2), "TeeterUnderlyingTOP: FUNDOPEN");
        //updatePrice();
        //calculate the amount of cap sent
        uint256 amtTokenIn = this.balanceOf(address(this));
        require(amtTokenIn > 0, "TeeterUnderlyingTOP: INSUFFICIENT_LPTIN");
        //=I41*AA42/(SUM(W$2:W41)-SUM(AA$2:AA41))
        amtToken0 = SafeMath.div(
            SafeMath.mul(underlyingQTY, amtTokenIn), 
            totalSupply
        );
        underlyingQTY -= amtToken0;//amtToken0=underlyingQTY*amtTokenIn/totalSupply amtTokenIn<totalSupply underlyingQTY>amtToken0 not need SafeMath
        //underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        uint256 balBase = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        //bal - ownerU, then send to cap by ratio
        amtU = SafeMath.div(
            //SafeMath.mul((balBase - ownerU), amtTokenIn), 
            SafeMath.mul(SafeMath.sub(balBase, ownerU), amtTokenIn), 
            totalSupply
        );
        //return asset of pool to the cap
        if(amtToken0 != 0){
            TransferHelper.safeTransfer(token0, to, TeeterLibrary.convert18ToOri(token0, amtToken0));
        }
        if(amtU != 0){
            //balBaseLast -= amtU;//update bal of base
            balBaseLast = SafeMath.sub(balBaseLast, amtU);
            //uint256 capUDelta = amtU*capU/(capU+underlyingU);
            uint256 capUDelta = SafeMath.div(SafeMath.mul(amtU, capU), (capU+underlyingU));
            capU -= capUDelta;//capUDelta<capU not need
            underlyingU =SafeMath.sub(underlyingU, SafeMath.sub(amtU,capUDelta));
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU));
        }
        _burn(address(this), amtTokenIn); 
    }
    
    function liquidationLT(address to)external lock returns(uint256 amtU){
        require(status == 2, "TeeterUnderlyingTOP: NOT FORCE CLOSE");
        uint256 amtLeverTokenIn = IERC20(leverage).balanceOf(address(this));
        require(amtLeverTokenIn >0, "TeeterUnderlyingTOP: balance0Err");
        //updatePrice();
        //underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        uint256 leverTotalSupply = IERC20(leverage).totalSupply();

        //usrMarginU=L39-L39*R40/(SUM(T$2:T39)-SUM(U$2:U39))
        //amtU = SafeMath.div(amtLeverTokenIn*usrMarginU, leverTotalSupply);
        amtU = SafeMath.div(SafeMath.mul(amtLeverTokenIn, usrMarginU), leverTotalSupply);
        usrMarginU -= amtU;//usrMarginU>amtU amtLeverTokenIn<leverTotalSupply not need

        if(amtU != 0){
            //balBaseLast -= amtU;//update bal of base
            balBaseLast = SafeMath.sub(balBaseLast, amtU);
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU));
        }
        ITeeterLeverage(leverage).burn(address(this), amtLeverTokenIn);
    }

    function cake(bool isTransfer)external returns(uint256 amtU){
        require((msg.sender == ITeeterFactory(factory).owner()) && ( ownerU > 0 || feeU > 0), "TeeterUnderlyingTOP: FORBIDDEN");
        //=O13+N13*(1-$W$44)
        //capU += ((feeU * (5192296858534827628530496329220096 - ownerRateEn))>>112);
        capU += (SafeMath.mul(feeU, SafeMath.sub(5192296858534827628530496329220096, ownerRateEn))>>112);
        //=AC13+N13*$W$44
        //ownerU += ((feeU * ownerRateEn)>>112);
        ownerU += (SafeMath.mul(feeU, ownerRateEn)>>112);
        amtU = ownerU;
        feeU = 0;
        if(isTransfer){
            //balBaseLast -= amtU;//update bal of base
            balBaseLast = SafeMath.sub(balBaseLast, amtU);
            ownerU = 0;
            TransferHelper.safeTransfer(addrBase, ITeeterFactory(factory).owner(), TeeterLibrary.convert18ToOri(addrBase, amtU));
        }
    }

    function closeForced()external returns(uint8 fundStatus){
        require(msg.sender == ITeeterFactory(factory).owner(), "TeeterUnderlying: FORBIDDEN");
        status = 2;
        //uint256 feeUOwner = (feeU*(5192296858534827628530496329220096-ownerRateEn))>>112;
        uint256 feeUOwner = (SafeMath.mul(feeU, SafeMath.sub(5192296858534827628530496329220096, ownerRateEn)))>>112;
        ownerU += feeUOwner;
        //capU = balBaseLast - ownerU - underlyingU - usrMarginU;
        capU = SafeMath.sub(balBaseLast, (ownerU + underlyingU + usrMarginU));
        feeU = 0;
        fundSoldValueEn = 0;
        fundSoldQTY = 0;
        nvEn = 0;
        presLeverEn = 0;
        //usrMarginU = 0;
        usrPoolQ = 0;
        capPoolU = 0;
        price0En = priceEn;
        fundStatus = status;
    }     
}
