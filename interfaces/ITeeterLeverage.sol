pragma solidity ^0.5.6;

interface ITeeterLeverage {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function nonces(address owner) external view returns (uint);
    function initialize(address) external;
    function mint(address, uint256)external;
    function burn(address, uint256)external;
    function underlying()external view returns (address);
    function factory()external view returns (address);
}
