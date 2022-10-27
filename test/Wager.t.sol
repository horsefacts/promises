// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "forge-std/Test.sol";
import "../src/Promises.sol";

contract Token is ERC20("Token", "TOKEN", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Oracle {
    uint256 _price = 1000;

    function price() external view returns (uint256) {
        return _price;
    }

    function setPrice(uint256 value) external {
        _price = value;
    }
}

contract Resolver {
    Oracle public oracle;

    constructor(Oracle _oracle) {
        oracle = _oracle;
    }

    function resolve() external view returns (bool) {
        return oracle.price() > 2000;
    }
}

contract WagerTest is Test {
    Promises public promises;
    Token public token;
    Oracle public oracle;
    Resolver public resolver;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        promises = new Promises();
        token = new Token();
        oracle = new Oracle();
        resolver = new Resolver(oracle);

        token.mint(alice, 1000 ether);
    }

    function set_up_wager() public {
        // Alice makes a wager with Bob: The price of some token returned by
        // an oracle contract will exceed 2000 some time in the next 30 days.

        // Promise expiration is 30 days from now.
        uint64 expire = uint64(block.timestamp) + 30 days;

        // Call the resolver contract to resolve the promise.
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, ())
        });

        // If the promise is fulfilled, Alice wins the bet. Encode a call that
        // transfers the wager amount from the promise proxy back to Alice.
        Call memory fulfill = Call({
            target: address(token),
            callData: abi.encodeCall(token.transfer, (alice, 1000 ether))
        });

        // If the promise is rejected, Bob wins the bet. Encode a call that
        // transfers the wager amount from the promise proxy to Bob.
        Call memory reject = Call({
            target: address(token),
            callData: abi.encodeCall(token.transfer, (bob, 1000 ether))
        });

        vm.startPrank(alice);
        promises.make(expire, resolve, fulfill, reject);
        PromiseProxy proxy = promises.proxy(1);

        // Alice sends the wager amount to the promise proxy.
        token.transfer(address(proxy), 1000 ether);

        // Alice's token balance is now zero
        assertEq(token.balanceOf(alice), 0);

        // Promise proxy token balance is now 1000
        assertEq(token.balanceOf(address(proxy)), 1000 ether);

        // Alice sends the reject token to Bob.
        promises.transferFrom(alice, bob, 2);

        vm.stopPrank();
    }

    function test_alice_wins() public {
        set_up_wager();

        // Alice cannot fulfill the promise, since price is not > 1000.
        vm.expectRevert(Forbidden.selector);
        vm.prank(alice);
        promises.fulfill(1);

        // Bob cannot reject the promise, since it has not expired.
        vm.expectRevert(Forbidden.selector);
        vm.prank(bob);
        promises.reject(1);

        // Price increases to 1500
        oracle.setPrice(1500);

        // Alice still cannot fulfill the promise.
        vm.expectRevert(Forbidden.selector);
        vm.prank(alice);
        promises.fulfill(1);

        // Bob still cannot reject the promise, since it has not expired.
        vm.expectRevert(Forbidden.selector);
        vm.prank(bob);
        promises.reject(1);

        // Price increases to 2001
        oracle.setPrice(2001);

        // Alice can now fulfill the promise.
        vm.prank(alice);
        promises.fulfill(1);

        // Alice's token balance is now 1000
        assertEq(token.balanceOf(alice), 1000 ether);

        // Promise proxy token balance is now zero
        PromiseProxy proxy = promises.proxy(1);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function test_bob_wins() public {
        set_up_wager();

        vm.warp(block.timestamp + 10 days);

        // Alice cannot fulfill the promise, since price is not > 1000.
        vm.expectRevert(Forbidden.selector);
        vm.prank(alice);
        promises.fulfill(1);

        // Bob cannot reject the promise, since it has not expired.
        vm.expectRevert(Forbidden.selector);
        vm.prank(bob);
        promises.reject(1);

        vm.warp(block.timestamp + 10 days);

        // Price increases to 1500
        oracle.setPrice(1500);

        // Alice still cannot fulfill the promise.
        vm.expectRevert(Forbidden.selector);
        vm.prank(alice);
        promises.fulfill(1);

        // Bob still cannot reject the promise, since it has not expired.
        vm.expectRevert(Forbidden.selector);
        vm.prank(bob);
        promises.reject(1);

        vm.warp(block.timestamp + 10 days + 1);

        // Alice still cannot fulfill the promise.
        vm.expectRevert(Forbidden.selector);
        vm.prank(alice);
        promises.fulfill(1);

        // Bob can now reject the promise.
        vm.prank(bob);
        promises.reject(1);

        // Alice's token balance is still zero
        assertEq(token.balanceOf(alice), 0);

        // Promise proxy token balance is now zero
        PromiseProxy proxy = promises.proxy(1);
        assertEq(token.balanceOf(address(proxy)), 0);

        // Bob's token balance is now 1000
        assertEq(token.balanceOf(bob), 1000 ether);
    }
}
