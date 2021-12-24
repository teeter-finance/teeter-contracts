pragma solidity =0.5.16;

import "./interfaces/ITeeterFactory.sol";
import "./interfaces/ITeeterFactoryInfo.sol";

contract TeeterFactoryInfo is ITeeterFactoryInfo{

    address public factoryTOP;
    address public factoryNO;

    function setAddrs(address _factoryTOP, address _factoryNO)public{
        require(msg.sender == ITeeterFactory(_factoryTOP).owner(), "TeeterUnderlyingTOP: FORBIDDEN");
        factoryTOP = _factoryTOP;
        factoryNO = _factoryNO;
    }    
    

    /**
     * @dev get underlying address by start and count 
     */
    function getUnderlyingAddressesTOP(uint256 start, uint256 count) public view returns (address[] memory) {
        uint256 length = ITeeterFactory(factoryTOP).allUnderAddrsLength();
        if (length == 0) {
            // Return an empty array
            return new address[](0);
        } else {
            uint256 end = start + count;
            if(length < end) {
                end = length;
            }
            if(start >= end) {
                return new address[](0);
            }
            count = end - start;
            address[] memory result = new address[](count);
            uint256 index;
            for (index = start; index < end; index++) {
                result[index - start] = ITeeterFactory(factoryTOP).allUnderAddrs(index);
            }
            return result;
        }
    }

    function getUnderlyingAddressesNOTOP(uint256 start, uint256 count) public view returns (address[] memory) {
        uint256 length = ITeeterFactory(factoryNO).allUnderAddrsLength();
        if (length == 0) {
            // Return an empty array
            return new address[](0);
        } else {
            uint256 end = start + count;
            if(length < end) {
                end = length;
            }
            if(start >= end) {
                return new address[](0);
            }
            count = end - start;
            address[] memory result = new address[](count);
            uint256 index;
            for (index = start; index < end; index++) {
                result[index - start] = ITeeterFactory(factoryNO).allUnderAddrs(index);
            }
            return result;
        }
    }    
    

}
