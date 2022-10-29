// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import "forge-std/Test.sol";
import "../src/Promises.sol";

contract Token is ERC20("Token", "TOKEN", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Lock is IResolve, IFulfill, IReject {
    Token public immutable token;

    constructor(Token _token) {
        token = _token;
    }

    // The resolve function always returns false. This
    // promise can only be rejected after it expires.
    function resolve() external pure returns (bool) {
        return false;
    }

    // This promise cannot be fulfilled.
    function fulfill(address, address) external pure {
        revert Forbidden();
    }

    // After expiration, the short may withdraw the locked
    // balance.
    function reject(address, address short) external {
        token.transfer(short, token.balanceOf(address(this)));
    }
}

contract CallTest is Test {
    Promises public promises;
    Token public token;
    Lock public lock;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        promises = new Promises();
        token = new Token();
        lock = new Lock(token);

        token.mint(alice, 1000 ether);
    }

    function set_up_lock() public {
        // Alice locks tokens for 90 days.

        // Promise expiration is 90 days from now.
        uint64 expire = uint64(block.timestamp) + 90 days;

        vm.startPrank(alice);
        promises.make(expire, address(lock));
        PromiseProxy proxy = promises.proxy(1);

        // Alice sends her tokens to the promise proxy.
        token.transfer(address(proxy), 1000 ether);
        vm.stopPrank();
    }

    function test_alice_creates_lock() public {
        set_up_lock();

        // Fulfilling reverts
        vm.startPrank(alice);
        vm.expectRevert(Forbidden.selector);
        promises.fulfill(1);

        // Rejecting before expiration reverts
        vm.expectRevert(Forbidden.selector);
        promises.reject(1);

        // Warp past expiration
        vm.warp(block.timestamp + 90 days + 1);

        // Alice can reject and withdraw the locked tokens
        promises.reject(1);

        // Tokens are transferred back to Alice
        assertEq(token.balanceOf(alice), 1000 ether);
        vm.stopPrank();
    }
}
