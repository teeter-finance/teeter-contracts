pragma solidity =0.5.16;

import "./interfaces/ITeeterUnderlying.sol";
import "./TeeterERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TeeterLibrary.sol";
import "./interfaces/IERC20.sol";
import './interfaces/ITeeterLeverage.sol';
import './interfaces/ITeeterFactory.sol';
import './libraries/TransferHelper.sol';

// the init version do not take fee management into consideration 
contract TeeterUnderlying is ITeeterUnderlying, TeeterERC20 {
    address[] public exchangeAddrs;
    address public factory; 
    address public leverage;
    address public token0;
    uint256 private underlyingQTY;
    uint256 private underlyingValueEn;
    uint256 private fundSoldQTY;
    uint256 private fundSoldValueEn;
    uint256 private fundAvaiQTY;
    uint256 private fundAvaiValueEn;
    uint256 public price0En;
    uint256 public priceEn;
    uint256 public purcRateEn;
    uint256 public redeeRateEn;
    uint256 public manaRateEn;
    uint256 public liquDiscountRateEn;
    uint256 public ownerRateEn;
    address public addrBase;
    uint256 public balBaseLast;//local
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
    uint256 private refNvEn;
    uint256 private usrPoolQ;
    uint256 public ownerU;

    uint256 private unlocked = 1;
    
    constructor() public {
        factory = msg.sender;
    }

    modifier lock() {
        require(unlocked == 1, "TeeterUnderlying: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function initialize(
        address _token0, uint8 _lever, uint8 _direction,
        address _leverage, uint256 _purcRateEn, uint256 _redeeRateEn, uint256 _manaRateEn,
        address _addrBase, uint256 _liquDiscountRateEn, uint256 _ownerRateEn, address _pair
        ) external {
        require(msg.sender == factory, "TeeterUnderlying: FORBIDDEN");
        token0 = _token0;
        initLever = _lever;
        presLeverEn = uint256(_lever)<<112;
        direction = _direction;
        leverage = _leverage;
        purcRateEn = _purcRateEn;
        redeeRateEn = _redeeRateEn;
        manaRateEn = _manaRateEn;
        addrBase = _addrBase;
        refNvEn = nvEn;
        liquDiscountRateEn = _liquDiscountRateEn;
        ownerRateEn = _ownerRateEn;
        price0En = priceEn;
        symbol =  "bcTeeter";
        name = symbol;
        exchangeAddrs.push(_pair);
        exchangeAddrs.push(address(0x0));
    }

    function updateParameter(
        uint256 _purcRateEn, uint256 _redeeRateEn, uint256 _manaRateEn, uint256 _liquDiscountRateEn, 
        uint256 _ownerRateEn, address exchangeAddr0, address exchangeAddr1
        ) external {
        //the caller must be factory contract
        require(msg.sender == ITeeterFactory(factory).owner(), "TeeterUnderlying: FORBIDDEN");
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
        uint256 _fundAvaiValueEn, 
        uint256 _fundSoldQTY, 
        uint256 _fundAvaiQTY, 
        uint256 _nvEn, 
        uint256 _presLeverEn, 
        uint256 _underlyingQTY, 
        uint256 _priceEn, 
        uint256 _underlyingValueEn, 
        uint256 _capPoolU, 
        uint256 _usrMarginU,
        uint256 _feeU,
        uint256 _capU,
        uint256 _usrPoolQ){
        _fundSoldValueEn = fundSoldValueEn;
        _fundAvaiValueEn = fundAvaiValueEn;
        _fundSoldQTY = fundSoldQTY;
        _fundAvaiQTY = fundAvaiQTY;
        _nvEn  = nvEn;
        _presLeverEn = presLeverEn;
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
        fundAvaiValueEn = SafeMath.sub(SafeMath.div(underlyingValueEn, presLeverEn)<<112, fundSoldValueEn);
        fundAvaiQTY = SafeMath.div(fundAvaiValueEn, refNvEn);
        capU += capPoolU;
        capPoolU = 0;
    }

    function _rebalanceU()private{
        uint256 _initLeverEn = uint256(initLever)<<112;
        refNvEn = nvEn;
        uint256 sub1En = SafeMath.div(underlyingValueEn, _initLeverEn)<<112;
        if(sub1En > fundSoldValueEn){
            fundAvaiValueEn = sub1En-fundSoldValueEn;
            fundAvaiQTY = SafeMath.div(fundAvaiValueEn, refNvEn);
        }else{
            fundAvaiValueEn = 0;
            fundAvaiQTY = 0;
        }
        presLeverEn = SafeMath.div(fundAvaiValueEn, fundSoldQTY);
    }

    function _updateIndexes() public{//local, kovan be private
        require(fundSoldQTY >0 || fundAvaiQTY>0,"TeeterUnderlying: QTY_EMPTY");
        if(status == 1){
            uint timeElapsed = block.timestamp - blockTimestampLast; 
            uint daysEn = SafeMath.div(timeElapsed<<112, 86400);//86400 one day secs
            //fee =M8+L8*$G$34
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
                uint256 _underlyingAdjEn = SafeMath.sub(underlyingValueEn, _underlyingValueLastEn);
                uint256 _soldValueAdjEn = SafeMath.div(SafeMath.mul(_underlyingAdjEn>>112, fundSoldQTY), (fundSoldQTY+fundAvaiQTY))<<112;
                fundSoldValueEn += _soldValueAdjEn ;
                fundSoldValueEn = SafeMath.sub(fundSoldValueEn, SafeMath.sub(feeU, feeLast)<<112);
                
                uint256 _avaiValueAdjEn = SafeMath.div(SafeMath.mul(_underlyingAdjEn>>112, fundAvaiQTY), (fundSoldQTY+fundAvaiQTY))<<112 ; 
                fundAvaiValueEn += _avaiValueAdjEn ;
            }else{
                uint256 _underlyingAdjEn = SafeMath.sub(_underlyingValueLastEn, underlyingValueEn);
                uint256 _soldValueAdjEn = SafeMath.div(SafeMath.mul(_underlyingAdjEn>>112, fundSoldQTY), (fundSoldQTY+fundAvaiQTY))<<112 ;
                fundSoldValueEn -= _soldValueAdjEn ;
                fundSoldValueEn = SafeMath.sub(fundSoldValueEn, SafeMath.sub(feeU, feeLast)<<112);
                
                uint256 _avaiValueAdjEn = SafeMath.div(SafeMath.mul(_underlyingAdjEn>>112, fundAvaiQTY), (fundSoldQTY+fundAvaiQTY))<<112 ; 
                fundAvaiValueEn -= _avaiValueAdjEn ;
            }
            if((fundAvaiValueEn+fundSoldValueEn)>=underlyingValueEn){
                status = 0;
                ownerU += ((feeU*(5192296858534827628530496329220096-ownerRateEn))>>112);
                capU = balBaseLast - ownerU;
                fundSoldValueEn = 0;
                fundSoldQTY = 0;
                fundAvaiValueEn = 0;
                fundAvaiQTY = 0;
                nvEn = 0;
                presLeverEn = 0;
                usrMarginU = 0;
                usrPoolQ = 0;
                capPoolU = 0;
                feeU = 0;
                price0En = priceEn;
            }else{
                if(((fundSoldQTY - 1) < fundSoldQTY) && fundSoldQTY>1){
                    nvEn = SafeMath.div(fundSoldValueEn, fundSoldQTY);
                }else{
                    nvEn = SafeMath.div(fundAvaiValueEn, fundAvaiQTY);
                }
                uint256 sub2 = feeU + capU + (fundSoldValueEn>>112) + ownerU;
                if(balBaseLast <= sub2){ capPoolU = 0;}else{ capPoolU = SafeMath.sub(balBaseLast, sub2); }
                require( balBaseLast >= (capPoolU + feeU + capU + ownerU),"feeOrcapUERR");
                usrMarginU = SafeMath.sub(balBaseLast, (capPoolU + feeU + capU + ownerU));
                uint256 sub1En = ((feeU + capU + ownerU)<<112) + fundSoldValueEn;
                uint256 sub2En = balBaseLast<<112;
                if(sub1En>sub2En){ 
                    uint256 numeratorEn = SafeMath.sub(sub1En, sub2En);
                    usrPoolQ = SafeMath.div(numeratorEn, priceEn);
                }else{
                    usrPoolQ = 0;
                }
                price0En = priceEn;
                presLeverEn = SafeMath.div(underlyingValueEn, ((fundSoldValueEn + fundAvaiValueEn)>>112));     
                if(SafeMath.mul(5, nvEn) <= refNvEn){ _rebalanceD(); }else if(SafeMath.div(nvEn, 4) >= refNvEn){_rebalanceU();}                    
            }
        }else{
            price0En = priceEn;
            underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        }
        blockTimestampLast = block.timestamp;
    }

    function mint(address to) external lock returns(uint256 liquidity){
        require(status == 1, "TeeterUnderlying: FUNDCLOSE");
        uint256 balance0 = TeeterLibrary.convertTo18(token0, IERC20(token0).balanceOf(address(this)));
        uint256 amount0 = SafeMath.sub(balance0, underlyingQTY);
        require((amount0 > 1000000000), "TeeterUnderlying: INSUFFICIENT_AMOUNT");//min is 1000000000, the unit not sure
        updatePrice();
        if(totalSupply == 0){
            require(priceEn!=0, "TEETER_PRICEIS0");
            presLeverEn = uint256(initLever)<<112;
            liquidity = SafeMath.mul(amount0, priceEn)>>112;
            underlyingQTY = amount0;
            underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
            fundAvaiQTY = SafeMath.div(underlyingValueEn, presLeverEn);
            fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);
            blockTimestampLast = block.timestamp;
            blockTimestampInit = block.timestamp;
            price0En = priceEn;
        }else{
            _updateIndexes();
            if(status != 1){TransferHelper.safeTransfer(token0, to, TeeterLibrary.convert18ToOri(token0, amount0)); return 0;}
            uint256 numerator = SafeMath.mul(
                SafeMath.mul(amount0, priceEn)>>112, 
                totalSupply
            );
            uint256 sub1 = (underlyingValueEn>>112) + capPoolU + ((feeU*(5192296858534827628530496329220096-ownerRateEn))>>112) + capU;
            uint256 sub2 = SafeMath.mul(usrPoolQ, priceEn)>>112;
            uint256 denominator = SafeMath.add(sub1, sub2);
            liquidity = SafeMath.div(numerator, denominator);
            require(liquidity !=0, 'TeeterUnderlying:LPTERR');
            underlyingQTY += amount0;
            underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
            uint256 numerator1En = SafeMath.mul(amount0, priceEn);
            uint256 numerator2 = SafeMath.div(numerator1En, nvEn);
            fundAvaiQTY += SafeMath.div(numerator2<<112, presLeverEn);
            fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);

        }
        _mint(to, liquidity);
        
    }

    function purchase(address to) external lock returns(uint256 amtLever){
        require(status == 1, "TeeterUnderlying: FUNDCLOSE");
        updatePrice();
        uint256 balanceBase = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        require(balanceBase != 0, "TeeterUnderlying: balanceBaseIS0");
        uint256 amtTokenIn = SafeMath.sub(balanceBase, balBaseLast);
        require((amtTokenIn > 1000000000000000000), "TeeterUnderlying: INSUFFICIENT_AMTTOKENIN");//min is 1U
        _updateIndexes();
        if(status != 1){TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtTokenIn)); return 0;}//if close return token0
        uint256 numeratorEn = SafeMath.mul(fundAvaiQTY, nvEn);
        uint256 denominatorEn = SafeMath.sub(5192296858534827628530496329220096, purcRateEn);
        uint256 amtMaxPurc = SafeMath.div(numeratorEn, denominatorEn);
        if(amtTokenIn > amtMaxPurc){
            uint256 amtTokenInReturn = TeeterLibrary.convert18ToOri(addrBase, SafeMath.sub(amtTokenIn, amtMaxPurc));
            TransferHelper.safeTransfer(addrBase, to, amtTokenInReturn);
            balanceBase -= (amtTokenIn - amtMaxPurc); 
            amtTokenIn = amtMaxPurc;
        }
        amtLever = SafeMath.div(
            SafeMath.sub(
                amtTokenIn<<112, SafeMath.mul(amtTokenIn, purcRateEn)
            ), 
            nvEn
        );
        require((amtLever !=0), "TeeterUnderlying: INSUFFICIENT_FUNDAVAI");
        uint256 feeULast = feeU;
        feeU += (SafeMath.mul(amtTokenIn, purcRateEn)>>112);
        uint256 sub1 = usrMarginU + amtTokenIn;
        uint256 sub2 = SafeMath.sub(feeU, feeULast);
        usrMarginU = SafeMath.sub(sub1, sub2);
        uint256 exTotalQTY = fundAvaiQTY + fundSoldQTY;
        fundAvaiQTY -= amtLever;
        fundSoldQTY = exTotalQTY - fundAvaiQTY;
        fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);
        fundSoldValueEn = SafeMath.mul(fundSoldQTY, nvEn);
        balBaseLast = balanceBase;
        ITeeterLeverage(leverage).mint(to, amtLever);
    }

    function redeem(address to) external lock returns(uint256 amtAsset, uint256 amtU){
        require(status == 1, "TeeterUnderlying: FUNDCLOSE");
        require(fundAvaiQTY>0 || fundSoldQTY>0, "TeeterUnderlying: FUNDQTYERR");
        updatePrice();
        uint256 amtLeverTokenIn = IERC20(leverage).balanceOf(address(this));
        require(amtLeverTokenIn !=0, "TeeterUnderlying: INSUFFICIENT_amtLeverTokenIn");
        _updateIndexes();
        if(status != 1){TransferHelper.safeTransfer(leverage, to, amtLeverTokenIn); return (0, 0);}//if close return token0
        uint256 feeULast = feeU;
        feeU += (
            SafeMath.mul(
                SafeMath.mul(amtLeverTokenIn, nvEn)>>112, 
                redeeRateEn
            )>>112
        );
        uint256 feeUIncrement = SafeMath.sub(feeU, feeULast);
        uint256 leverTotalSupply = IERC20(leverage).totalSupply();
        amtU = SafeMath.sub(
            SafeMath.div(
                SafeMath.mul(usrMarginU, amtLeverTokenIn), 
                leverTotalSupply
            ), 
            feeUIncrement
        );
        amtAsset = SafeMath.div(SafeMath.mul(usrPoolQ, amtLeverTokenIn), leverTotalSupply);
        usrPoolQ -= amtAsset;
        uint256 capULast = capU;
        capU += SafeMath.div(SafeMath.mul(capPoolU, amtLeverTokenIn), leverTotalSupply);
        uint256 sub2 = SafeMath.div(SafeMath.mul(amtLeverTokenIn, usrMarginU), leverTotalSupply);
        usrMarginU = SafeMath.sub(usrMarginU, sub2);
        capPoolU = SafeMath.sub(capPoolU, SafeMath.sub(capU, capULast));
        underlyingQTY -= amtAsset;
        uint256 exTotalQTY = fundAvaiQTY + fundSoldQTY;
        fundAvaiQTY += amtLeverTokenIn;
        fundSoldQTY = exTotalQTY - fundAvaiQTY;
        fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);
        fundSoldValueEn = SafeMath.mul(fundSoldQTY, nvEn);
        ITeeterLeverage(leverage).burn(address(this), amtLeverTokenIn);
        presLeverEn = SafeMath.div(underlyingValueEn, (fundSoldValueEn + fundAvaiValueEn)>>112);
        if(amtAsset !=0 ){
            amtAsset = TeeterLibrary.convert18ToOri(token0, amtAsset);
            TransferHelper.safeTransfer(token0, to, amtAsset);
        }
        if(amtU != 0){
            balBaseLast -= amtU;//update bal of base
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU)); 
        }

    }

    function recycle(address to) external lock returns(uint256 amtToken0, uint256 amtU){
        require(status == 1, "TeeterUnderlying: FUNDCLOSE");
        updatePrice();
        uint256 amtLPT = this.balanceOf(address(this));
        require((amtLPT>0), "TeeterUnderlying: BALANCEERR");
        uint256 amtMaxRecy = SafeMath.div(
            SafeMath.mul(fundAvaiQTY, totalSupply), 
            SafeMath.add(fundAvaiQTY, fundSoldQTY)
        );
        if(amtLPT > amtMaxRecy){
            uint256 amtLPTReturn;
            amtLPTReturn = SafeMath.sub(amtLPT, amtMaxRecy);
            TransferHelper.safeTransfer(address(this), to, amtLPTReturn);
            amtLPT = amtMaxRecy;
        }
        _updateIndexes();
        if(status != 1){TransferHelper.safeTransfer(address(this), to, amtLPT); return (0, 0);}//if close return token0 don't revert
        uint256 sum1 = SafeMath.div(
            SafeMath.mul(
                SafeMath.sub(underlyingQTY, usrPoolQ), amtLPT
            ), 
            totalSupply
        );
        uint256 numerator = SafeMath.mul(capPoolU, amtLPT);
        uint256 denominatorEn = SafeMath.mul(totalSupply, priceEn);
        uint256 sum2 = SafeMath.div(numerator<<112, denominatorEn);
        amtToken0 = SafeMath.add(sum1 ,sum2);
        uint256 subOwnerRateEn = SafeMath.sub(5192296858534827628530496329220096, ownerRateEn);
        numerator = 
            SafeMath.mul(
                (SafeMath.mul(feeU, subOwnerRateEn) + (capU<<112))>>112, 
                amtLPT
            );
        amtU = SafeMath.div(numerator, totalSupply);
        require((amtU + amtToken0) != 0, "TeeterUnderlying: INSUFFICIENT_UorToken0");
        ownerU += SafeMath.div(
            SafeMath.mul(
                SafeMath.mul(feeU, ownerRateEn)>>112, 
                amtLPT
            ),
            totalSupply
        );
        uint256 sub2 = SafeMath.div(
            SafeMath.mul(capU, amtLPT), 
            totalSupply
        );
        capU = SafeMath.sub(capU, sub2);
        uint256 increment = SafeMath.div(SafeMath.mul(feeU, amtLPT), totalSupply);
        require(feeU >= increment, "TeeterUnderlying: INSUFFICIENT_fee");
        feeU -= increment;
        underlyingQTY -= amtToken0;
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        numerator = SafeMath.mul(SafeMath.add(fundAvaiQTY, fundSoldQTY), amtLPT);
        fundAvaiQTY -= SafeMath.div(numerator, totalSupply);
        fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);
        _burn(address(this), amtLPT); 
        if(amtToken0 != 0){
            amtToken0 = TeeterLibrary.convert18ToOri(token0, amtToken0);
            TransferHelper.safeTransfer(token0, to, amtToken0);
        }
        if(amtU != 0){
            balBaseLast -= amtU;
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU));
        }

    }

    function liquidation3Part(address to)external lock returns(uint256 amtToken0){
        require(status == 0, "TeeterUnderlying: FUNDOPEN");
        uint256 amtMaxLiqu = SafeMath.mul(underlyingValueEn>>112, liquDiscountRateEn)>>112;
        updatePrice();
        uint256 balanceBase = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        require(balanceBase != 0, "TeeterUnderlying: balanceBaseErr");
        uint256 amtTokenIn = SafeMath.sub(balanceBase, balBaseLast);
        if(amtTokenIn > amtMaxLiqu){
            uint256 amtTokenInReturn = SafeMath.sub(amtTokenIn, amtMaxLiqu);
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtTokenInReturn));
            balanceBase -= amtTokenInReturn; 
            amtTokenIn = amtMaxLiqu;
        }
        amtToken0 = SafeMath.div(
            SafeMath.div(amtTokenIn<<112, liquDiscountRateEn)<<112, 
            priceEn
        );
        require(amtToken0 !=0, "TeeterUnderlying: INSUFFICIENT_TOKEN0AVAI");//no enough token be sold
        underlyingQTY -= amtToken0;
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        balBaseLast = balanceBase;
        capU += amtTokenIn;
        if(amtToken0 !=0){
            TransferHelper.safeTransfer(token0, to, TeeterLibrary.convert18ToOri(token0, amtToken0));
        }

    }

    function liquidationLPT(address to)external lock returns(uint256 amtToken0, uint256 amtU){
        require((status == 0 || status == 2), "TeeterUnderlying: FUNDOPEN");
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        require(balance0 >0, "TeeterUnderlying: balance0Err");
        updatePrice();
        uint256 amtTokenIn = this.balanceOf(address(this));
        require(amtTokenIn > 0, "TeeterUnderlying: INSUFFICIENT_LPTIN");
        uint256 sub2 = SafeMath.div(
            SafeMath.mul(underlyingQTY, amtTokenIn), 
            totalSupply
        );
        uint256 underlyingQTYLast = underlyingQTY;
        underlyingQTY -= sub2;
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        uint256 balBase = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        amtU = SafeMath.div(
            SafeMath.mul((balBase - ownerU), amtTokenIn), 
            totalSupply
        );
        amtToken0 = SafeMath.sub(underlyingQTYLast, underlyingQTY);
        if(amtToken0 != 0){
            TransferHelper.safeTransfer(token0, to, TeeterLibrary.convert18ToOri(token0, amtToken0));
        }
        if(amtU != 0){
            balBaseLast -= amtU;
            capU -= amtU;
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU));
        }
        _burn(address(this), amtTokenIn); 
    }
    
    function liquidationLT(address to)external lock returns(uint256 amtU){
        require(status == 2, "TeeterUnderlying: NOT FORCE CLOSE");
        uint256 amtLeverTokenIn = IERC20(leverage).balanceOf(address(this));
        require(amtLeverTokenIn >0, "TeeterUnderlying: balance0Err");
        updatePrice();
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        uint256 leverTotalSupply = IERC20(leverage).totalSupply();
        amtU = SafeMath.div(amtLeverTokenIn*usrMarginU, leverTotalSupply);
        usrMarginU -= amtU;

        if(amtU != 0){
            balBaseLast -= amtU;
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU));
        }
        _burn(address(this), amtLeverTokenIn); 
    }

    function cake(bool isTransfer)external returns(uint256 amtU){
        require((msg.sender == ITeeterFactory(factory).owner()) && ( ownerU > 0 || feeU > 0), "TeeterUnderlying: FORBIDDEN");
        capU += ((feeU * (5192296858534827628530496329220096 - ownerRateEn))>>112);
        ownerU += ((feeU * ownerRateEn)>>112);
        amtU = ownerU;
        feeU = 0;
        if(isTransfer){
            balBaseLast -= amtU;
            ownerU = 0;
            TransferHelper.safeTransfer(addrBase, ITeeterFactory(factory).owner(), TeeterLibrary.convert18ToOri(addrBase, amtU));
        }
    }

    function closeForced()external returns(uint8 fundStatus){
        require(msg.sender == ITeeterFactory(factory).owner(), "TeeterUnderlying: FORBIDDEN");
        status = 2;
        ownerU += ((feeU*(5192296858534827628530496329220096-ownerRateEn))>>112);
        capU = balBaseLast - ownerU;
        fundSoldValueEn = 0;
        fundSoldQTY = 0;
        fundAvaiValueEn = 0;
        fundAvaiQTY = 0;
        nvEn = 0;
        presLeverEn = 0;
        //usrMarginU = 0;
        usrPoolQ = 0;
        capPoolU = 0;
        feeU = 0;
        price0En = priceEn;
        fundStatus = status;
    }    
}
