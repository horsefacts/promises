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

contract Oracle {
    bool _completed;

    function completed() external view returns (bool) {
        return _completed;
    }

    function setCompleted(bool value) external {
        _completed = value;
    }
}

contract Commitment is IResolve, IFulfill, IReject {
    Token public immutable token;
    Oracle public immutable oracle;

    constructor(Token _token, Oracle _oracle) {
        token = _token;
        oracle = _oracle;
    }

    // The long side of this commitment contract has agreed
    // to do some thing (as reported by an onchain oracle)
    // before expiration. If they meet the commitment, they
    // may withdraw their escrowed tokens. If they do not,
    // the tokens will be burned.
    function resolve() external view returns (bool) {
        return oracle.completed();
    }

    // If the commitment is met, transfer the contract's
    // token balance to the long.
    function fulfill(address long,address) external {
        token.transfer(long, token.balanceOf(address(this)));
    }


    // If the commitment is not met, burn the token balance.
    function reject(address, address) external {
        token.transfer(address(0xdead), token.balanceOf(address(this)));
    }
}

contract CommitmentTest is Test {
    Promises public promises;
    Token public token;
    Oracle public oracle;
    Commitment public commitment;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        promises = new Promises();
        token = new Token();
        oracle = new Oracle();
        commitment = new Commitment(token, oracle);

        token.mint(alice, 1000 ether);
    }

    function set_up_commitment() public {
        // Alice pledges to do $THING within 30 days.
        // She locks up 1000 tokens that will be lost
        // if she fails to meet her commitment.

        // Promise expiration is 30 days from now.
        uint64 expire = uint64(block.timestamp) + 30 days;

        vm.startPrank(alice);
        promises.make(expire, address(commitment));
        PromiseProxy proxy = promises.proxy(1);

        // Alice sends her tokens to the promise proxy.
        token.transfer(address(proxy), 1000 ether);
        vm.stopPrank();

    }

    function test_alice_meets_commitment() public {
        set_up_commitment();

        // Alice meets her commitment and the oracle
        // now returns true.
        oracle.setCompleted(true);

        // Alice fulfills the promise and withdraws
        // her tokens.
        vm.prank(alice);
        promises.fulfill(1);

        assertEq(token.balanceOf(alice), 1000 ether);
    }

    function test_alice_does_not_meet_commitment() public {
        set_up_commitment();

        // Warp past expiration without meeting the commitment.
        vm.warp(block.timestamp + 30 days + 1);

        // Alice cannot withdraw her tokens.
        vm.expectRevert(Forbidden.selector);
        vm.prank(alice);
        promises.fulfill(1);

        // The short token holder can reject the promise to
        // burn the tokens.
        vm.prank(alice);
        promises.reject(1);

        assertEq(token.balanceOf(alice), 0);
    }

    function test_alice_transfers_commitment() public {
        set_up_commitment();

        // Alice transfers the long side of her commitment
        // to Bob. Now if Alice meets her goal, Bob gets
        // the escrowed tokens.
        vm.prank(alice);
        promises.transferFrom(alice, bob, 1);

        // Alice meets her commitment and the oracle
        // now returns true.
        oracle.setCompleted(true);

        // Bob fulfills the promise and withdraws
        // the tokens.
        vm.prank(bob);
        promises.fulfill(1);

        assertEq(token.balanceOf(bob), 1000 ether);
    }
}
