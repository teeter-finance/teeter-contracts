pragma solidity =0.5.16;

import "./TeeterERC20.sol";
import "./interfaces/ITeeterLeverage.sol";
//import "./libraries/TeeterLibrary.sol";
import "./interfaces/IERC20.sol";


contract TeeterLeverage is ITeeterLeverage, TeeterERC20 {
    address public factory; 
    //address public token0; 
    //uint8 public direction;
    //uint8 public initLever;
    address public underlying; 

    uint256 private unlocked = 1;
    /**
     * @dev keep from double entry
     */
    modifier lock() {
        require(unlocked == 1, "TeeterUnderlying: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }   
    
    constructor() public {
        //factory address == the address of user who imp the contract. msg.sender == address of factory
        factory = msg.sender;
    }

    function initialize(address _underlying) external {
        //确认调用者为工厂地址
        require(msg.sender == factory, "Teeter: FORBIDDEN");
        //token0 = _token0;
        //initLever = _lever;
        //direction = _direction;
        underlying = _underlying;
        //symbol =  TeeterLibrary.strMulJoin('x', IERC20(token0).symbol());
        symbol = 'xTeeter';
        name = symbol;
        //name = TeeterLibrary.strMulJoin('Teeter_', IERC20(token0).symbol(), '_', IERC20(addrBase).symbol(), '_3L');
    }

    function mint(address to, uint256 value)external lock {
        require(msg.sender == underlying, 'TeeterLeverage:ADDRESS_FORBIDDEN');
        _mint(to, value);
    }

    function burn(address from, uint256 value)external lock {
        require(msg.sender == underlying, 'TeeterLeverage:ADDRESS_FORBIDDEN');
        _burn(from, value);
    }
}
