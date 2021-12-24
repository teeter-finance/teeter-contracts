pragma solidity =0.5.16;

interface ITeeterFactory {

    function underAddr(address token, uint8 lever, uint8 direction) external view returns (address);
    function owner() external view returns (address);
    function addrBase() external view returns (address);
    function allUnderAddrs(uint) external view returns (address underlying);
    function purcRateEn() external view returns (uint);
    function redeeRateEn() external view returns (uint);
    function manaRateEn() external view returns (uint);
    function liquDiscountRateEn() external view returns (uint);
    function allUnderAddrsLength() external view returns (uint);
    function tokenTops(address _token) external view returns (bool);

    function updateParameterForUpcoming(
        uint256 _purcRateEn, uint256 _redeeRateEn, uint256 _manaRateEn, uint256 _liquDiscountRateEn,
        uint256 _ownerRateEn, address _addrBase
        )external;
    function createUnderlying(
        address token0, uint8 lever, uint8 direction) external returns (address underlying, address leverage);
    //function getUnderlyingAddresses(uint256 start, uint256 count) external view returns (address[] memory);
    function setTopToken(address _token, bool _bool)external;
}
