pragma solidity >=0.4.23;

import "erc20/erc20.sol";

abstract contract WETHEvents is ERC20Events {
    event Join(address indexed dst, uint wad);
    event Exit(address indexed src, uint wad);
}

abstract contract WETH is ERC20, WETHEvents {
    function join() virtual public payable;
    function exit(uint wad) virtual public;
}
