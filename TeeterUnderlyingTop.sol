pragma solidity =0.5.16;

import "./interfaces/ITeeterUnderlyingTop.sol";
import "./interfaces/ITeeterFactory.sol";
import "./TeeterERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TeeterLibrary.sol";
import "./interfaces/IERC20.sol";
import './interfaces/ITeeterLeverage.sol';
import './libraries/TransferHelper.sol';

contract TeeterUnderlyingTop is ITeeterUnderlyingTop, TeeterERC20 {
    address[] public exchangeAddrs;
    address public factory;
    address public leverage;
    address public token0;
    uint256 public capAddU;
    uint256 public underlyingU;
    uint256 private underlyingQTY;
    uint256 private underlyingValueEn;
    uint256 private fundSoldQTY;
    uint256 private fundSoldValueEn;
    uint256 public price0En;
    uint256 public priceEn;
    uint256 public purcRateEn;
    uint256 public redeeRateEn;
    uint256 public manaRateEn;
    uint256 public liquDiscountRateEn;
    uint256 public ownerRateEn;
    address public addrBase;
    uint256 public balBaseLast;
    uint256 private nvEn = 5192296858534827628530496329220096;
    uint8 public initLever;
    uint256 private presLeverEn;
    uint8 public direction;
    
    uint8 public status = 1;
    uint private blockTimestampLast;
    uint public blockTimestampInit;
    uint256 private capPoolU;
    uint256 private feeU;
    uint256 private usrMarginU;
    uint256 private capU;
    uint256 public refNvEn = 5192296858534827628530496329220096;
    uint256 private usrPoolQ;
    uint256 public ownerU;

    uint256 public exePrice;

    uint256 private unlocked = 1;
    
    constructor() public {
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
        require(msg.sender == factory, "TeeterUnderlyingTOP: FORBIDDEN");
        token0 = _token0;
        initLever = _lever;
        presLeverEn = uint256(_lever)<<112;
        direction = _direction;
        leverage = _leverage;
        purcRateEn = _purcRateEn;
        redeeRateEn = _redeeRateEn;
        manaRateEn = _manaRateEn;
        addrBase = _addrBase;
        liquDiscountRateEn = _liquDiscountRateEn;
        ownerRateEn = _ownerRateEn;
        symbol = 'bTeeter';
        exchangeAddrs.push(_pair);
        exchangeAddrs.push(address(0x0));
    }

    function updateParameter(
        uint256 _purcRateEn, uint256 _redeeRateEn, uint256 _manaRateEn, uint256 _liquDiscountRateEn, 
        uint256 _ownerRateEn, address exchangeAddr0, address exchangeAddr1
        ) external {
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

    function updatePrice()public {
        priceEn = TeeterLibrary.getLastPriceEn(token0, exchangeAddrs);
    }
    
    function _rebalanceD()private{
        presLeverEn = uint256(initLever)<<112;
        refNvEn = nvEn;
        usrMarginU = SafeMath.sub(usrMarginU, capPoolU);
        uint256 underlyingQTYlast = underlyingQTY;
        underlyingQTY = SafeMath.div(SafeMath.mul(usrMarginU, presLeverEn), priceEn);
        if(underlyingQTY > underlyingQTYlast){return;}
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        _swap((underlyingQTYlast-underlyingQTY), token0);
        uint256 swapU = SafeMath.sub(
            TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this))), balBaseLast
        );
        balBaseLast += swapU;  
        underlyingU += swapU;
        capU += capPoolU;
        capPoolU = 0;

    }

    function _rebalanceU() private{
        refNvEn = nvEn;
        uint256 swapQ;
        uint256 sub1En = SafeMath.mul(
            (SafeMath.sub(usrMarginU, capPoolU) + (SafeMath.mul(usrPoolQ, priceEn)>>112)), 
            uint256(initLever)<<112
        );
        uint256 underlyingUDelta = SafeMath.sub(sub1En, underlyingValueEn);
        if(underlyingU > underlyingUDelta){
            underlyingU -= underlyingUDelta;
        }else{
            underlyingUDelta = underlyingU;
            underlyingU = 0;
        }
        _swap(underlyingUDelta, addrBase);
        swapQ = SafeMath.sub(
            TeeterLibrary.convertTo18(token0, IERC20(token0).balanceOf(address(this))), underlyingQTY
        );
        balBaseLast = SafeMath.sub(balBaseLast, underlyingUDelta);
        underlyingQTY += swapQ;
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        presLeverEn = SafeMath.div(underlyingValueEn, fundSoldValueEn>>112);
        capU += capPoolU;
        capPoolU = 0;
    }
    

    function _updateIndexes() public{//local, kovan be private
        require(fundSoldQTY >0 || underlyingU>0,"TeeterUnderlyingTOP: EMPTY");
        if(price0En==priceEn || fundSoldValueEn==0){return;}
        if(status == 1){
            uint timeElapsed = SafeMath.sub(block.timestamp, blockTimestampLast);
            uint daysEn = SafeMath.div((timeElapsed)<<112, 86400);
            uint256 feeLast = feeU;
            feeU += (
                SafeMath.mul(
                    usrMarginU, 
                    SafeMath.mul(manaRateEn, daysEn)>>112
                )>>112
            );
            uint256 _underlyingValueLastEn = underlyingValueEn;
            underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
            if(priceEn > price0En){
                fundSoldValueEn += SafeMath.sub(underlyingValueEn, _underlyingValueLastEn) ;
            }else{
                fundSoldValueEn = SafeMath.sub(fundSoldValueEn, SafeMath.sub(_underlyingValueLastEn, underlyingValueEn));
            }
            fundSoldValueEn = SafeMath.sub(fundSoldValueEn, (SafeMath.sub(feeU, feeLast))<<112);
            if(fundSoldValueEn>underlyingValueEn){
                status = 0;
                ownerU += (SafeMath.mul(
                    feeU, 
                    SafeMath.sub(5192296858534827628530496329220096, ownerRateEn))>>112
                );
                capU = SafeMath.sub(balBaseLast, (ownerU + underlyingU));
                feeU = 0;
                fundSoldValueEn = 0;
                fundSoldQTY = 0;
                nvEn = 0;
                presLeverEn = 0;
                usrMarginU = 0;
                usrPoolQ = 0;
                capPoolU = 0;
                price0En = priceEn;
            }else{
                if(fundSoldQTY!=0){
                    nvEn = SafeMath.div(fundSoldValueEn, fundSoldQTY);
                    presLeverEn = SafeMath.div(underlyingValueEn, fundSoldValueEn>>112);                         
                }
                usrMarginU =SafeMath.sub(usrMarginU, (feeU-feeLast));//feeU been added in line 214, so feeU > feeLast. here not need safeMath for feeU
                uint256 fundSoldValue = fundSoldValueEn>>112;
                if(fundSoldValue >= usrMarginU){
                    capPoolU = 0;
                }else{
                    capPoolU = usrMarginU - fundSoldValue;
                }
                if(fundSoldValue >= usrMarginU){
                    usrPoolQ = SafeMath.div( ((fundSoldValue-usrMarginU)<<112), priceEn);
                }else{
                    usrPoolQ = 0;
                }
                price0En = priceEn;
                if(SafeMath.mul(5, nvEn) <= refNvEn){ _rebalanceD(); }else if(SafeMath.div(nvEn, 3) >= refNvEn){_rebalanceU();}
            }
        }else{
            price0En = priceEn;
            underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        }
        blockTimestampLast = block.timestamp;
    }

    function mint(address to) external lock returns(uint256 liquidity){
        require(status == 1, "TeeterUnderlyingTOP: FUNDCLOSE");
        uint256 baseBal = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        uint256 baseAmt = SafeMath.sub(baseBal, balBaseLast);
        capAddU += baseAmt;
        require((baseAmt > 10000000), "TeeterUnderlyingTOP: INSUFFICIENT_baseBal");
        updatePrice();
        if(totalSupply == 0){
            require(priceEn!=0, "TEETER_PRICEIS0");
            nvEn = 5192296858534827628530496329220096;
            presLeverEn =15576890575604482885591488987660288;
            liquidity = baseAmt;
            underlyingU = baseAmt;
            blockTimestampLast = block.timestamp;
            blockTimestampInit = block.timestamp;
            price0En = priceEn;
        }else{
            _updateIndexes();
            if(status != 1){TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, baseAmt)); return 0;}
            uint256 feeUCaked = SafeMath.mul(feeU, SafeMath.sub(5192296858534827628530496329220096, ownerRateEn))>>112;
            uint256 numerator = SafeMath.mul(baseAmt, totalSupply);
            uint256 sub1 = (underlyingValueEn>>112) + capPoolU + feeUCaked + capU + underlyingU;
            uint256 sub2 = SafeMath.mul(usrPoolQ, priceEn)>>112;
            uint256 denominator = SafeMath.sub(sub1, sub2);
            liquidity = SafeMath.div(numerator, denominator);
            require(liquidity !=0, 'TeeterUnderlying:LPTERR');
            underlyingU += baseAmt;
        }
        balBaseLast = baseBal;
        _mint(to, liquidity);
    }
    

    function purchase(address to) external lock returns(uint256 amtLever){
        require(status == 1, "TeeterUnderlyingTOP: FUNDCLOSE");
        updatePrice();
        uint256 balanceBase = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        require(balanceBase != 0, "TeeterUnderlyingTOP: balanceBaseIS0");
        uint256 amtTokenIn = SafeMath.sub(balanceBase, balBaseLast);
        require((amtTokenIn > 10000000000000000000), "TeeterUnderlyingTOP: INSUFFICIENT_AMTTOKENIN");
        _updateIndexes();
        if(status != 1){TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtTokenIn)); return 0;}//if close return token0
        uint256 amtMaxPurc = SafeMath.div(underlyingU<<112, presLeverEn);
        if(amtTokenIn > amtMaxPurc){
            uint256 amtTokenInReturn = TeeterLibrary.convert18ToOri(addrBase, SafeMath.sub(amtTokenIn, amtMaxPurc));
            TransferHelper.safeTransfer(addrBase, to, amtTokenInReturn);
            balanceBase -= (amtTokenIn - amtMaxPurc);
            amtTokenIn = amtMaxPurc;
        }
        uint256 feeUDelta = SafeMath.mul(amtTokenIn, purcRateEn)>>112;
        feeU += feeUDelta;
        uint256 amtTokenInFeed = SafeMath.sub(amtTokenIn, feeUDelta);
        uint256 deltaUnderlyingU = SafeMath.mul(amtTokenInFeed, presLeverEn)>>112;
        underlyingU = SafeMath.sub(underlyingU, deltaUnderlyingU) ;
        _swap(deltaUnderlyingU, addrBase);
        uint256 deltaUnderlyingQTY = SafeMath.sub(
            TeeterLibrary.convertTo18(token0, IERC20(token0).balanceOf(address(this))), underlyingQTY
        );        
        underlyingQTY += deltaUnderlyingQTY;
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        uint256 amtTokenInFeedLeveEn = deltaUnderlyingU<<112;
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
        if(amtTokenInFeedLeveEn > deltaUnderlyingQTYValueEn){
            capU += ((amtTokenInFeedLeveEn - deltaUnderlyingQTYValueEn)>>112);//already judged before, so don’t need safeMath here.
        }
        amtLever = SafeMath.div(
            SafeMath.sub(
                amtTokenInFeed<<112, 
                SafeMath.sub(amtTokenInFeedLeveEn, deltaUnderlyingQTYValueEn)
            ), 
            nvEn
        );
        fundSoldQTY += amtLever;
        fundSoldValueEn = SafeMath.mul(fundSoldQTY, nvEn);
        balBaseLast = SafeMath.sub(SafeMath.add(balBaseLast, amtTokenIn), deltaUnderlyingU);//the price of Q maybe change, need to check
        ITeeterLeverage(leverage).mint(to, amtLever);
    }
    
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

        if(_path0 == addrBase){
            exePrice = SafeMath.div(TeeterLibrary.convertTo18(path[0], amounts0[0]), TeeterLibrary.convertTo18(path[1], amounts0[1]));
        }else{
            exePrice = SafeMath.div(TeeterLibrary.convertTo18(path[1], amounts0[1]), TeeterLibrary.convertTo18(path[0], amounts0[0]));
        }
    }

    function redeem(address to) external lock returns(uint256 amtAsset, uint256 amtU){
        require(status == 1, "TeeterUnderlyingTOP: FUNDCLOSE");
        updatePrice();
        uint256 amtLeverTokenIn = IERC20(leverage).balanceOf(address(this));
        require(amtLeverTokenIn !=0, "TeeterUnderlyingTOP: INSUFFICIENT_amtLeverTokenIn");
        _updateIndexes();
        if(status != 1){TransferHelper.safeTransfer(leverage, to, amtLeverTokenIn); return (0, 0);}//if close return token0
        uint256 feeUDelta = 
            SafeMath.mul(
                SafeMath.mul(amtLeverTokenIn, nvEn)>>112, 
                redeeRateEn
            )>>112;
        feeU += feeUDelta;
        uint256 leverTotalSupply = IERC20(leverage).totalSupply();
        uint256 swapU;
        uint256 amtLeverTokenInValue = SafeMath.mul(amtLeverTokenIn, priceEn)>>112;
        underlyingU = underlyingU + SafeMath.div(SafeMath.mul(amtLeverTokenInValue, SafeMath.sub(underlyingQTY, usrPoolQ)), leverTotalSupply);
        uint256 underlyingQTYlast = underlyingQTY;
        underlyingQTY = SafeMath.sub(
            underlyingQTY, 
            SafeMath.div(
                SafeMath.mul(underlyingQTY, amtLeverTokenIn), leverTotalSupply
            )
        ); 

        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        _swap((underlyingQTYlast-underlyingQTY), token0);// underlyingQTY has been subed, so not need SafeMath here 
        swapU = SafeMath.sub(
            TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this))), balBaseLast
        );
        {
        uint256 sum1 = SafeMath.sub(
            SafeMath.div(
                SafeMath.mul(SafeMath.sub(usrMarginU, capPoolU), amtLeverTokenIn), leverTotalSupply
            ), feeUDelta);
        uint256 sum2 = SafeMath.div(SafeMath.mul(amtLeverTokenInValue, usrPoolQ), leverTotalSupply); 
        uint256 sum3 = SafeMath.div(SafeMath.mul(amtLeverTokenInValue, underlyingQTYlast), leverTotalSupply);
        require((sum1 + sum2) > SafeMath.sub(sum3, swapU), "TeeterUnderlyingTOP:INSUFFICIENT AMOUNT U");
        amtU = sum1 + sum2 - SafeMath.sub(sum3, swapU);
        }
        uint256 sub2 = SafeMath.div(SafeMath.mul(amtLeverTokenIn, usrMarginU), leverTotalSupply);
        usrMarginU = SafeMath.sub(usrMarginU, sub2);
        capU = SafeMath.add(capU, SafeMath.div(SafeMath.mul(capPoolU, amtLeverTokenIn), leverTotalSupply));
        capPoolU = SafeMath.sub(
            capPoolU, 
            SafeMath.div(SafeMath.mul(capPoolU, amtLeverTokenIn), leverTotalSupply)
        );
        usrPoolQ = SafeMath.sub(usrPoolQ, SafeMath.div(SafeMath.mul(usrPoolQ, amtLeverTokenIn), leverTotalSupply)); 
        fundSoldQTY = SafeMath.sub(fundSoldQTY, amtLeverTokenIn);
        fundSoldValueEn = SafeMath.mul(fundSoldQTY, nvEn);
        ITeeterLeverage(leverage).burn(address(this), amtLeverTokenIn);
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
        if(status != 1){TransferHelper.safeTransfer(address(this), to, amtLPT); return (0, 0);}
        uint256 hon = underlyingU + capU + (SafeMath.mul(feeU, SafeMath.sub(5192296858534827628530496329220096, ownerRateEn))>>112);
        uint256 ipjl = (SafeMath.mul(SafeMath.sub(underlyingQTY, usrPoolQ), priceEn)>>112) + capPoolU;
        uint256 poolValue = hon + ipjl;
        uint256 amtMaxRecy = SafeMath.div(SafeMath.mul(totalSupply, hon), poolValue);
        if(amtLPT > amtMaxRecy){
            uint256 amtLPTReturn;
            amtLPTReturn = amtLPT - amtMaxRecy;//has judged before
            TransferHelper.safeTransfer(address(this), to, amtLPTReturn);
            amtLPT = amtMaxRecy;
        }
        amtU = SafeMath.div(SafeMath.mul(amtLPT, poolValue), totalSupply);
        ownerU += SafeMath.div(SafeMath.mul(SafeMath.mul(ownerRateEn, amtLPT)>>112, feeU), totalSupply);
        capU = SafeMath.sub(
            capU, 
            SafeMath.div(SafeMath.mul(amtU, capU), hon)
        );
        feeU -= SafeMath.div(SafeMath.mul(feeU, amtLPT), totalSupply);//feeU > feeU*amtLPT/totalSupply, amtLPT<totalSupply not need SafeMath
        underlyingU = SafeMath.sub(underlyingU, SafeMath.div(SafeMath.mul(amtU, underlyingU), hon));
        _burn(address(this), amtLPT); 
        if(amtU != 0){
            balBaseLast = SafeMath.sub(balBaseLast, amtU);//update bal of base
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
        amtToken0 = SafeMath.div(
            SafeMath.div(amtTokenIn<<112, liquDiscountRateEn)<<112, 
            priceEn
        );
        underlyingQTY = SafeMath.sub(underlyingQTY, amtToken0);
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        balBaseLast = balanceBase;//update bal of base
        capU += amtTokenIn;
        if(amtToken0 !=0){
            TransferHelper.safeTransfer(token0, to, TeeterLibrary.convert18ToOri(token0, amtToken0));
        }

    }

    function liquidationLPT(address to)external lock returns(uint256 amtToken0, uint256 amtU){
        require((status == 0 || status == 2), "TeeterUnderlyingTOP: FUNDOPEN");
        uint256 amtTokenIn = this.balanceOf(address(this));
        require(amtTokenIn > 0, "TeeterUnderlyingTOP: INSUFFICIENT_LPTIN");
        amtToken0 = SafeMath.div(
            SafeMath.mul(underlyingQTY, amtTokenIn), 
            totalSupply
        );
        underlyingQTY -= amtToken0;
        uint256 balBase = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        amtU = SafeMath.div(
            SafeMath.mul(SafeMath.sub(balBase, ownerU), amtTokenIn), 
            totalSupply
        );
        if(amtToken0 != 0){
            TransferHelper.safeTransfer(token0, to, TeeterLibrary.convert18ToOri(token0, amtToken0));
        }
        if(amtU != 0){
            balBaseLast = SafeMath.sub(balBaseLast, amtU);
            uint256 capUDelta = SafeMath.div(SafeMath.mul(amtU, capU), (capU+underlyingU));
            capU -= capUDelta;
            underlyingU =SafeMath.sub(underlyingU, SafeMath.sub(amtU,capUDelta));
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU));
        }
        _burn(address(this), amtTokenIn); 
    }
    
    function liquidationLT(address to)external lock returns(uint256 amtU){
        require(status == 2, "TeeterUnderlyingTOP: NOT FORCE CLOSE");
        uint256 amtLeverTokenIn = IERC20(leverage).balanceOf(address(this));
        require(amtLeverTokenIn >0, "TeeterUnderlyingTOP: balance0Err");
        uint256 leverTotalSupply = IERC20(leverage).totalSupply();
        amtU = SafeMath.div(SafeMath.mul(amtLeverTokenIn, usrMarginU), leverTotalSupply);
        usrMarginU -= amtU;
        if(amtU != 0){
            balBaseLast = SafeMath.sub(balBaseLast, amtU);
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU));
        }
        ITeeterLeverage(leverage).burn(address(this), amtLeverTokenIn);
    }

    function cake(bool isTransfer)external returns(uint256 amtU){
        require((msg.sender == ITeeterFactory(factory).owner()) && ( ownerU > 0 || feeU > 0), "TeeterUnderlyingTOP: FORBIDDEN");
        capU += (SafeMath.mul(feeU, SafeMath.sub(5192296858534827628530496329220096, ownerRateEn))>>112);
        ownerU += (SafeMath.mul(feeU, ownerRateEn)>>112);
        amtU = ownerU;
        feeU = 0;
        if(isTransfer){
            balBaseLast = SafeMath.sub(balBaseLast, amtU);
            ownerU = 0;
            TransferHelper.safeTransfer(addrBase, ITeeterFactory(factory).owner(), TeeterLibrary.convert18ToOri(addrBase, amtU));
        }
    }

    function closeForced()external returns(uint8 fundStatus){
        require(msg.sender == ITeeterFactory(factory).owner(), "TeeterUnderlying: FORBIDDEN");
        status = 2;
        uint256 feeUOwner = (SafeMath.mul(feeU, SafeMath.sub(5192296858534827628530496329220096, ownerRateEn)))>>112;
        ownerU += feeUOwner;
        capU = SafeMath.sub(balBaseLast, (ownerU + underlyingU + usrMarginU));
        feeU = 0;
        fundSoldValueEn = 0;
        fundSoldQTY = 0;
        nvEn = 0;
        presLeverEn = 0;
        usrPoolQ = 0;
        capPoolU = 0;
        price0En = priceEn;
        fundStatus = status;
    }     
}
