pragma solidity =0.5.16;

interface ITeeterFactoryInfo {


    function setAddrs(address _factoryTOP, address _factoryNO)external;
    function getUnderlyingAddressesTOP(uint256 start, uint256 count) external view returns (address[] memory);
    function getUnderlyingAddressesNOTOP(uint256 start, uint256 count) external view returns (address[] memory);
}
