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
    address public factory; //address of factory
    address public leverage;
    address public token0; //address of quote token
    uint256 private underlyingQTY;
    uint256 private underlyingValueEn;
    uint256 private fundSoldQTY;
    uint256 private fundSoldValueEn;
    uint256 private fundAvaiQTY;
    uint256 private fundAvaiValueEn;
    uint256 public price0En;
    uint256 public priceEn;
    uint256 public purcRateEn;//purchase fee rate 
    uint256 public redeeRateEn;//redeem fee rate 
    uint256 public manaRateEn;//management fee rate 
    uint256 public liquDiscountRateEn;//discount rate 
    uint256 public ownerRateEn;//owner management fee rate
    address public addrBase;
    uint256 public balBaseLast;//local
    uint256 private nvEn = 5192296858534827628530496329220096 ;//fixed point adj
    uint8 public initLever;
    uint256 private presLeverEn;//fixed point adj
    uint8 public direction;
    
    uint8 public status = 1;// 1 active; 0 nagative;
    uint private blockTimestampLast;//have value in update function
    uint public blockTimestampInit;//have value in update function
    uint256 private capPoolU;//accrued blone to capital
    uint256 private feeU;//Transaction Fee + Fund management fee
    uint256 private usrMarginU; //the user margin USDT/DAI, user tuansfered in underlying contract for puchase leverage token
    uint256 private capU; //the U belone to cap
    uint256 private refNvEn;
    uint256 private usrPoolQ;
    uint256 public ownerU;

    uint256 private unlocked = 1;
    
    constructor() public {
        //msg.sender == factory contract address
        factory = msg.sender;
    }

    modifier lock() {
        require(unlocked == 1, "TeeterUnderlying: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }
    /**
     * @param _token0 token0
     * @param _lever lever
     * @param _direction direction
     * @dev execute by factory contract just once in deploy
     */
    function initialize(
        address _token0, uint8 _lever, uint8 _direction,
        address _leverage, uint256 _purcRateEn, uint256 _redeeRateEn, uint256 _manaRateEn,
        address _addrBase, uint256 _liquDiscountRateEn, uint256 _ownerRateEn, address _pair
        ) external {
        //the caller must be factory contract
        require(msg.sender == factory, "TeeterUnderlying: FORBIDDEN");
        token0 = _token0;
        initLever = _lever;
        presLeverEn = uint256(_lever)<<112;//3<<112
        direction = _direction;
        leverage = _leverage;
        purcRateEn = _purcRateEn;
        redeeRateEn = _redeeRateEn;
        manaRateEn = _manaRateEn;
        addrBase = _addrBase;
        refNvEn = nvEn;
        liquDiscountRateEn = _liquDiscountRateEn;
        ownerRateEn = _ownerRateEn;
        //updatePrice();
        //require(priceEn!=0, "TEETER_PRICEIS0");
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

    /**
     * @return _reserve0 
     * @return _blockTimestampLast 
     * @dev fetch reserve
     */
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

    function updatePrice()public {// kovan for test public
        priceEn = TeeterLibrary.getLastPriceEn(token0, exchangeAddrs); //kovan
    }
    
    function _rebalanceD()private{
        presLeverEn = uint256(initLever)<<112;
        refNvEn = nvEn;
        //fundAvaiValueEn =J14/G14-B14 
        fundAvaiValueEn = SafeMath.sub(SafeMath.div(underlyingValueEn, presLeverEn)<<112, fundSoldValueEn);
        fundAvaiQTY = SafeMath.div(fundAvaiValueEn, refNvEn);
        capU += capPoolU;
        capPoolU = 0;
    }

    function _rebalanceU()private{
        uint256 _initLeverEn = uint256(initLever)<<112;
        refNvEn = nvEn;
        //=IF(J30/G$2>B30,J30/G$2-B30,0)
        //if(underlyingValueEn/_initLeverEn>fundSoldValueEn, underlyingValueEn/_initLeverEn-fundSoldValueEn, 0)
        uint256 sub1En = SafeMath.div(underlyingValueEn, _initLeverEn)<<112;
        if(sub1En > fundSoldValueEn){
            fundAvaiValueEn = sub1En-fundSoldValueEn;
            //=C30/F30
            fundAvaiQTY = SafeMath.div(fundAvaiValueEn, refNvEn);
        }else{
            fundAvaiValueEn = 0;
            fundAvaiQTY = 0;
        }
        //=J31/(B31+C31)
        presLeverEn = SafeMath.div(fundAvaiValueEn, fundSoldQTY);
    }

    /**
     *  from front and the value will has been expanded 2**112
     * @dev create fund or add assets to fund. xxEn should be sure has been expanded 2**112
     */
    function _updateIndexes() public{//local, kovan be private
        require(fundSoldQTY >0 || fundAvaiQTY>0,"TeeterUnderlying: QTY_EMPTY");
        //status == 1 means fund open
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
            //underlyingValueEn =I5*H5
            uint256 _underlyingValueLastEn = underlyingValueEn;
            underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
            //fundSoldValueEn =B4+(J5-J4)*D5/(D5+E5)-(M5-M4)
            //fundAvaiValueEn =C4+(J5-J4)*E5/(D5+E5)
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
            //fund close
            if((fundAvaiValueEn+fundSoldValueEn)>=underlyingValueEn){
                status = 0;
                ownerU += ((feeU*(5192296858534827628530496329220096-ownerRateEn))>>112);
                //capU += (usrMarginU + capPoolU + capU + feeLast);//all U belone to cap former
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
                //nvEn =IF(OR(D3>0,E3>0),IF(D3>0,B3/D3,C3/E3),0)
                //negative judgment by overflow
                if(((fundSoldQTY - 1) < fundSoldQTY) && fundSoldQTY>1){
                    //B5/D5
                    nvEn = SafeMath.div(fundSoldValueEn, fundSoldQTY);
                }else{
                    //C5/E5
                    nvEn = SafeMath.div(fundAvaiValueEn, fundAvaiQTY);
                }
                //capPoolU =IF(((SUM(Q$2:Q2)-SUM(V$2:V2))-M3-N3-B3-Z3)<0,0,(SUM(Q$2:Q2)-SUM(V$2:V2))-M3-N3-B3-Z3) balBaseLast-(feeU+capU+fundSoldValueEn+ownerU)
                uint256 sub2 = feeU + capU + (fundSoldValueEn>>112) + ownerU;
                if(balBaseLast <= sub2){ capPoolU = 0;}else{ capPoolU = SafeMath.sub(balBaseLast, sub2); }
                //=(SUM(Q$2:Q3)-SUM(V$2:V3))-K3-M3-N2-Z2 usrMarginU = balBaseLast-(capPoolU+feeU+capU+ownerU)
                require( balBaseLast >= (capPoolU + feeU + capU + ownerU),"feeOrcapUERR");
                usrMarginU = SafeMath.sub(balBaseLast, (capPoolU + feeU + capU + ownerU));
                //=IF(((M3+N3+B3+Z3)-(SUM(Q$2:Q2)-SUM(V$2:V2)))>0,((M3+N3+B3+Z3)-(SUM(Q$2:Q2)-SUM(V$2:V2)))/I3,0)
                //usrPoolQ = ((feeU + capU + fundSoldValueEn + ownerU)-balBaseLast)/priceEn
                uint256 sub1En = ((feeU + capU + ownerU)<<112) + fundSoldValueEn;
                uint256 sub2En = balBaseLast<<112;
                if(sub1En>sub2En){ 
                    uint256 numeratorEn = SafeMath.sub(sub1En, sub2En);
                    usrPoolQ = SafeMath.div(numeratorEn, priceEn);
                }else{
                    usrPoolQ = 0;
                }
                price0En = priceEn;
                //presLeverEn =IF((B5+C5),J5/(B5+C5),0)
                presLeverEn = SafeMath.div(underlyingValueEn, ((fundSoldValueEn + fundAvaiValueEn)>>112));     
                if(SafeMath.mul(5, nvEn) <= refNvEn){ _rebalanceD(); }else if(SafeMath.div(nvEn, 4) >= refNvEn){_rebalanceU();}                    
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
        require(status == 1, "TeeterUnderlying: FUNDCLOSE");
        //balance0 >= reserve0, token has been transfer to this contract before. in FrontDesk.sol
        uint256 balance0 = TeeterLibrary.convertTo18(token0, IERC20(token0).balanceOf(address(this)));
        //calculate the amount of cap sent
        uint256 amount0 = SafeMath.sub(balance0, underlyingQTY);
        require((amount0 > 1000000000), "TeeterUnderlying: INSUFFICIENT_AMOUNT");//min is 1000000000, the unit not sure
        updatePrice();
        if(totalSupply == 0){
            //require((capPoolU + feeU + usrMarginU +usrPoolQ)==0, "TeeterUnderlying: HASFEE");
            require(priceEn!=0, "TEETER_PRICEIS0");
            //nvEn = 5192296858534827628530496329220096;
            presLeverEn = uint256(initLever)<<112;
            liquidity = SafeMath.mul(amount0, priceEn)>>112;
            underlyingQTY = amount0;
            underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
            //=J2/G2/F2 nv is 1 by default 
            //amount0*priceEn/presLeverEn
            fundAvaiQTY = SafeMath.div(underlyingValueEn, presLeverEn);
            fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);
            blockTimestampLast = block.timestamp;
            blockTimestampInit = block.timestamp;
            price0En = priceEn;
        }else{
            //updatePrice();
            _updateIndexes();
            if(status != 1){TransferHelper.safeTransfer(token0, to, TeeterLibrary.convert18ToOri(token0, amount0)); return 0;}//if close return token0
            //=S8*I8*SUM(U$2:U7)/(J7+K7+M7+N7-O7*I8)
            //=S8*I8*SUM(U$2:U7)/(J7+K7+M7*(1-$U$44)+N7-O7*I8)
            //liquidity = amount0*priceEn*totalSupply/(underlyingValueEn+capPoolU+feeU*(1-ownerRateEn)+capU-usrPoolQ*priceEn)
            uint256 numerator = SafeMath.mul(
                //SafeMath.decode(SafeMath.mul(amount0, priceEn)), 
                SafeMath.mul(amount0, priceEn)>>112, 
                totalSupply
            );
            uint256 sub1 = (underlyingValueEn>>112) + capPoolU + ((feeU*(5192296858534827628530496329220096-ownerRateEn))>>112) + capU;
            //uint256 sub2 = SafeMath.decode(SafeMath.mul(usrPoolQ, priceEn));
            uint256 sub2 = SafeMath.mul(usrPoolQ, priceEn)>>112;
            uint256 denominator = SafeMath.add(sub1, sub2);
            liquidity = SafeMath.div(numerator, denominator);
            require(liquidity !=0, 'TeeterUnderlying:LPTERR');
            underlyingQTY += amount0;
            //underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
            underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
            //=E7+R8*I8/F8/G8 -> E7+R8*I8/(F8*G8)
            //uint256 numerator1En = SafeMath.mul(amount0, priceEn);
            uint256 numerator1En = SafeMath.mul(amount0, priceEn);
            uint256 numerator2 = SafeMath.div(numerator1En, nvEn);
            fundAvaiQTY += SafeMath.div(numerator2<<112, presLeverEn);
            //update fundAvaiValue because fundAvaiQTY has been changed
            //fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);
            fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);

        }
        _mint(to, liquidity); //add LPT to capital user
        
    }

    //if transfer base to underlying and exceed avai again procees revert. the token transfered before not be return until asset be add.
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
        //require(amtMaxPurc >= amtTokenIn, "TeeterUnderlying: EXCEEDMaxPurc");
        //return base token exceed max to user
        if(amtTokenIn > amtMaxPurc){
            uint256 amtTokenInReturn = TeeterLibrary.convert18ToOri(addrBase, SafeMath.sub(amtTokenIn, amtMaxPurc));
            TransferHelper.safeTransfer(addrBase, to, amtTokenInReturn);
            balanceBase -= (amtTokenIn - amtMaxPurc); 
            amtTokenIn = amtMaxPurc;
        }
        // REC_LEV=(Q4-Q4*$C$36)/F4 (amtTokenIn-amtTokenIn*purcRateEn)/nvEn
        amtLever = SafeMath.div(
            SafeMath.sub(
                amtTokenIn<<112, SafeMath.mul(amtTokenIn, purcRateEn)
            ), 
            nvEn
        );
        // amtLever ==0 the base not be return to the to address
        require((amtLever !=0), "TeeterUnderlying: INSUFFICIENT_FUNDAVAI");
        //feeU =M3+Q4*$C$36
        uint256 feeULast = feeU;
        feeU += (SafeMath.mul(amtTokenIn, purcRateEn)>>112);
        //usrMarginU =L3+Q4-Q4*$C$36 -> =L3+Q4-(feeU-feeULast)
        uint256 sub1 = usrMarginU + amtTokenIn;
        uint256 sub2 = SafeMath.sub(feeU, feeULast);
        usrMarginU = SafeMath.sub(sub1, sub2);
        //QTY optimization
        uint256 exTotalQTY = fundAvaiQTY + fundSoldQTY;
        //fundAvaiQTY=E5-S6
        fundAvaiQTY -= amtLever;
        //fundSoldQTY=D5+S6
        fundSoldQTY = exTotalQTY - fundAvaiQTY;
        //fundAvaiValueEn=E6*F6
        fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);
        //fundSoldValueEn=D6*F6
        fundSoldValueEn = SafeMath.mul(fundSoldQTY, nvEn);
        balBaseLast = balanceBase;
        //mint the leverage token and transfer to user
        ITeeterLeverage(leverage).mint(to, amtLever);
        //mint end
    }

    //user transfer leverage token to underlying contract for asset token return
    function redeem(address to) external lock returns(uint256 amtAsset, uint256 amtU){
        require(status == 1, "TeeterUnderlying: FUNDCLOSE");
        require(fundAvaiQTY>0 || fundSoldQTY>0, "TeeterUnderlying: FUNDQTYERR");
        updatePrice();
        uint256 amtLeverTokenIn = IERC20(leverage).balanceOf(address(this));
        require(amtLeverTokenIn !=0, "TeeterUnderlying: INSUFFICIENT_amtLeverTokenIn");
        _updateIndexes();
        if(status != 1){TransferHelper.safeTransfer(leverage, to, amtLeverTokenIn); return (0, 0);}//if close return token0
        //=M13+R14*F14*$E$36 feeU = amtLeverTokenIn*nvEn*redeeRateEn
        uint256 feeULast = feeU;
        feeU += (
            SafeMath.mul(
                SafeMath.mul(amtLeverTokenIn, nvEn)>>112, 
                redeeRateEn
            )>>112
        );
        uint256 feeUIncrement = SafeMath.sub(feeU, feeULast);
        //=IF(R14,L13*R14/((SUM(T$2:T13)-SUM(R$2:R13)))-(M14-M13),0)
        uint256 leverTotalSupply = IERC20(leverage).totalSupply();
        //L13*R14/(SUM(T$2:T13)-SUM(R$2:R13))-(M14-M13) usrMarginU*amtLeverTokenIn/leverTotalSupply-(feeU-feeULast)
        amtU = SafeMath.sub(
            SafeMath.div(
                SafeMath.mul(usrMarginU, amtLeverTokenIn), 
                leverTotalSupply
            ), 
            feeUIncrement
        );
        //=O13*R14/(SUM(T$2:T13)-SUM(R$2:R13)) amtAsset = usrPoolQ*amtLeverTokenIn/leverTotalSupply
        amtAsset = SafeMath.div(SafeMath.mul(usrPoolQ, amtLeverTokenIn), leverTotalSupply);
        //=O13-W14
        usrPoolQ -= amtAsset;
        //capU =N13+IF((SUM(T$2:T13)-SUM(R$2:R13)),K13*R14/(SUM(T$2:T13)-SUM(R$2:R13)),0)
        uint256 capULast = capU;
        capU += SafeMath.div(SafeMath.mul(capPoolU, amtLeverTokenIn), leverTotalSupply);
        //=IF((SUM(T$2:T13)-SUM(R$2:R13))>0,L13-R14/(SUM(T$2:T13)-SUM(R$2:R13))*L13,0)
        //usrMarginU = usrMarginU-amtLeverTokenIn/leverTotalSupply*usrMarginU
        //usrMarginU = usrMarginU-amtLeverTokenIn*usrMarginU/leverTotalSupply
        uint256 sub2 = SafeMath.div(SafeMath.mul(amtLeverTokenIn, usrMarginU), leverTotalSupply);
        usrMarginU = SafeMath.sub(usrMarginU, sub2);
        //capPoolU=K13-(N14-N13)
        //capPoolU -= SafeMath.sub(capULast, capU);
        capPoolU = SafeMath.sub(capPoolU, SafeMath.sub(capU, capULast));
        //=H13-W14
        underlyingQTY -= amtAsset;
        //QTY optimization
        uint256 exTotalQTY = fundAvaiQTY + fundSoldQTY;
        //=E13+R14
        fundAvaiQTY += amtLeverTokenIn;
        //=D13-R14
        fundSoldQTY = exTotalQTY - fundAvaiQTY;
        //=E14*F14
        fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);
        //=D14*F14
        fundSoldValueEn = SafeMath.mul(fundSoldQTY, nvEn);
        //burn leverage token
        ITeeterLeverage(leverage).burn(address(this), amtLeverTokenIn);
        //=J14/(B14+C14) 
        presLeverEn = SafeMath.div(underlyingValueEn, (fundSoldValueEn + fundAvaiValueEn)>>112);
        //return token0 to user
        if(amtAsset !=0 ){
            amtAsset = TeeterLibrary.convert18ToOri(token0, amtAsset);
            TransferHelper.safeTransfer(token0, to, amtAsset);
        }
        //return U to user
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
        //require((amtMaxRecy-1<amtMaxRecy) && (amtMaxRecy>=amtLPT), "TeeterUnderlying: EXCEEDMAXRECYCLE");
        if(amtLPT > amtMaxRecy){
            uint256 amtLPTReturn;
            amtLPTReturn = SafeMath.sub(amtLPT, amtMaxRecy);
            TransferHelper.safeTransfer(address(this), to, amtLPTReturn);
            amtLPT = amtMaxRecy;
        }
        //update fund indexes according the last price
        _updateIndexes();
        if(status != 1){TransferHelper.safeTransfer(address(this), to, amtLPT); return (0, 0);}//if close return token0 don't revert
        //amtToken0 =(H11-O11)*X12/(SUM(U$2:U11)-SUM(X$2:X11))+K11*X12/(SUM(U$2:U11)-SUM(X$2:X11))/I12
        //(underlyingQTY- usrPoolQ)*amtLPT/totalSupply+capPoolU*amtLPT/(totalSupply*priceEn)
        uint256 sum1 = SafeMath.div(
            SafeMath.mul(
                SafeMath.sub(underlyingQTY, usrPoolQ), amtLPT
                //underlyingQTY, amtLPT
            ), 
            totalSupply
        );
        uint256 numerator = SafeMath.mul(capPoolU, amtLPT);
        uint256 denominatorEn = SafeMath.mul(totalSupply, priceEn);
        uint256 sum2 = SafeMath.div(numerator<<112, denominatorEn);
        amtToken0 = SafeMath.add(sum1 ,sum2);
        //amtU =(M11*(1-$U$36)+N11)*X12/(SUM(U$2:U11)-SUM(X$2:X11)) (feeU*(1-ownerRateEn)+capU)*amtLPT/totalSupply
        uint256 subOwnerRateEn = SafeMath.sub(5192296858534827628530496329220096, ownerRateEn);
        numerator = 
            SafeMath.mul(
                (SafeMath.mul(feeU, subOwnerRateEn) + (capU<<112))>>112, 
                amtLPT
            );
        amtU = SafeMath.div(numerator, totalSupply);
        require((amtU + amtToken0) != 0, "TeeterUnderlying: INSUFFICIENT_UorToken0");//if amtU and amtToken0 == 0, revert. no need transfer any token to user
        //=Y11+M11*$U$36*X12/(SUM(U$2:U11)-SUM(X$2:X11)) ownerU=feeU*ownerRateEn*amtLPT/totalSupply
        ownerU += SafeMath.div(
            SafeMath.mul(
                SafeMath.mul(feeU, ownerRateEn)>>112, 
                amtLPT
            ),
            totalSupply
        );
        //=N11*(1-X12/(SUM(U$2:U11)-SUM(X$2:X11))) 
        //capU = capU*(1-amtLPT/totalSupply) = capU-capU*amtLPT/totalSupply
        uint256 sub2 = SafeMath.div(
            SafeMath.mul(capU, amtLPT), 
            totalSupply
        );
        capU = SafeMath.sub(capU, sub2);
        //=M11-(M11*(X12/(SUM(U$2:U11)-SUM(X$2:X11)))) feeU -= feeU*amtLPT/totalSupply
        uint256 increment = SafeMath.div(SafeMath.mul(feeU, amtLPT), totalSupply);
        require(feeU >= increment, "TeeterUnderlying: INSUFFICIENT_fee");
        feeU -= increment;
        //=H19-V20 underlyingQTY
        underlyingQTY -= amtToken0;
        //=H20*I20 underlyingValueEn
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        //=E11-(D11+E11)*X12/(SUM(U$2:U11)-SUM(X$2:X11)) fundAvaiQTY -= (fundAvaiQTY+fundSoldQTY)*amtLPT/totalSupply
        numerator = SafeMath.mul(SafeMath.add(fundAvaiQTY, fundSoldQTY), amtLPT);
        fundAvaiQTY -= SafeMath.div(numerator, totalSupply);
        //=E20*F20 fundAvaiValueEn
        fundAvaiValueEn = SafeMath.mul(fundAvaiQTY, nvEn);
        //burn liq token
        _burn(address(this), amtLPT); 
        // return asset token and U to cap user
        if(amtToken0 != 0){
            amtToken0 = TeeterLibrary.convert18ToOri(token0, amtToken0);
            TransferHelper.safeTransfer(token0, to, amtToken0);
        }
        if(amtU != 0){
            balBaseLast -= amtU;//update bal of base
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU));
        }

    }

    function liquidation3Part(address to)external lock returns(uint256 amtToken0){
        require(status == 0, "TeeterUnderlying: FUNDOPEN");
        uint256 amtMaxLiqu = SafeMath.mul(underlyingValueEn>>112, liquDiscountRateEn)>>112;
        updatePrice();
        uint256 balanceBase = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        require(balanceBase != 0, "TeeterUnderlying: balanceBaseErr");
        //LIQ_U
        uint256 amtTokenIn = SafeMath.sub(balanceBase, balBaseLast);
        //require(amtTokenIn <= amtMaxLiqu, "TeeterUnderlying: INSUFFICIENT_amtLiqu");
        if(amtTokenIn > amtMaxLiqu){
            uint256 amtTokenInReturn = SafeMath.sub(amtTokenIn, amtMaxLiqu);
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtTokenInReturn));
            balanceBase -= amtTokenInReturn; 
            amtTokenIn = amtMaxLiqu;
        }
        //=X26/$R$34/I26 amtToken0 = amtTokenIn/liquDiscountRateEn/priceEn;
        amtToken0 = SafeMath.div(
            SafeMath.div(amtTokenIn<<112, liquDiscountRateEn)<<112, 
            priceEn
        );
        require(amtToken0 !=0, "TeeterUnderlying: INSUFFICIENT_TOKEN0AVAI");//no enough token be sold
        underlyingQTY -= amtToken0;
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        balBaseLast = balanceBase;//update bal of base
        capU += amtTokenIn;
        //return asset of pool to the 3rd Part
        if(amtToken0 !=0){
            TransferHelper.safeTransfer(token0, to, TeeterLibrary.convert18ToOri(token0, amtToken0));
        }

    }

    function liquidationLPT(address to)external lock returns(uint256 amtToken0, uint256 amtU){
        require((status == 0 || status == 2), "TeeterUnderlying: FUNDOPEN");
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        require(balance0 >0, "TeeterUnderlying: balance0Err");
        updatePrice();
        //calculate the amount of cap sent
        uint256 amtTokenIn = this.balanceOf(address(this));
        require(amtTokenIn > 0, "TeeterUnderlying: INSUFFICIENT_LPTIN");
        //=IF((SUM(T2:T27)-SUM(W2:W27)),H27-H27*W28/(SUM(T2:T27)-SUM(W2:W27)),0) underlyingQTY=underlyingQTY- underlyingQTY*amtTokenIn/totalSupply
        uint256 sub2 = SafeMath.div(
            SafeMath.mul(underlyingQTY, amtTokenIn), 
            totalSupply
        );
        uint256 underlyingQTYLast = underlyingQTY;
        underlyingQTY -= sub2;
        underlyingValueEn = SafeMath.mul(underlyingQTY, priceEn);
        uint256 balBase = TeeterLibrary.convertTo18(addrBase, IERC20(addrBase).balanceOf(address(this)));
        //bal - ownerU, then send to cap by ratio
        amtU = SafeMath.div(
            SafeMath.mul((balBase - ownerU), amtTokenIn), 
            totalSupply
        );

        //=H27-H28
        amtToken0 = SafeMath.sub(underlyingQTYLast, underlyingQTY);
        //return asset of pool to the cap
        if(amtToken0 != 0){
            TransferHelper.safeTransfer(token0, to, TeeterLibrary.convert18ToOri(token0, amtToken0));
        }
        if(amtU != 0){
            balBaseLast -= amtU;//update bal of base
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

        //usrMarginU=L39-L39*R40/(SUM(T$2:T39)-SUM(U$2:U39))
        amtU = SafeMath.div(amtLeverTokenIn*usrMarginU, leverTotalSupply);
        usrMarginU -= amtU;

        if(amtU != 0){
            balBaseLast -= amtU;//update bal of base
            TransferHelper.safeTransfer(addrBase, to, TeeterLibrary.convert18ToOri(addrBase, amtU));
        }
        _burn(address(this), amtLeverTokenIn); 
    }

    function cake(bool isTransfer)external returns(uint256 amtU){
        require((msg.sender == ITeeterFactory(factory).owner()) && ( ownerU > 0 || feeU > 0), "TeeterUnderlying: FORBIDDEN");
        //=O13+N13*(1-$W$44)
        capU += ((feeU * (5192296858534827628530496329220096 - ownerRateEn))>>112);
        //=AC13+N13*$W$44
        ownerU += ((feeU * ownerRateEn)>>112);
        amtU = ownerU;
        feeU = 0;
        if(isTransfer){
            balBaseLast -= amtU;//update bal of base
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
