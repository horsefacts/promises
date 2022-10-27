// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Promises.sol";

contract Resolver {
    function resolve(bool value) external pure returns (bool) {
        return value;
    }
}

contract Noop {
    function noop() external pure {
        return;
    }
}

contract FulfillTarget {
    bool public called;

    function fulfill() external {
        called = true;
    }
}

contract RejectTarget {
    bool public called;

    function reject() external {
        called = true;
    }
}

contract PromisesTest is Test {
    Promises public promises;

    Resolver public resolver;
    Noop public noop;
    FulfillTarget public fulfillTarget;
    RejectTarget public rejectTarget;

    address eve = makeAddr("eve");

    function setUp() public {
        promises = new Promises();
        resolver = new Resolver();
        noop = new Noop();
        fulfillTarget = new FulfillTarget();
        rejectTarget = new RejectTarget();
    }

    function test_make_stores_promise() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, (true))
        });
        Call memory fulfill = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        Call memory reject = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        promises.make(expire, resolve, fulfill, reject);

        assertEq(promises.count(), 1);

        Promise memory created = promises.promises(1);
        assertEq(uint8(created.state), uint8(State.Pending));
        assertEq(created.expires, expire);

        assertEq(created.resolve.target, address(resolver));
        assertEq(
            created.resolve.callData, abi.encodeCall(resolver.resolve, (true))
        );

        assertEq(created.fulfill.target, address(noop));
        assertEq(created.fulfill.callData, abi.encodeCall(noop.noop, ()));

        assertEq(created.reject.target, address(noop));
        assertEq(created.reject.callData, abi.encodeCall(noop.noop, ()));
    }

    function test_fulfill_promise_reverts_not_found() public {
        vm.expectRevert(NotFound.selector);
        promises.fulfill(1);
    }

    function test_reject_promise_reverts_not_found() public {
        vm.expectRevert(NotFound.selector);
        promises.reject(1);
    }

    function test_fulfill_promise_reverts_forbidden_after_expired() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, (true))
        });
        Call memory fulfill = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        Call memory reject = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        promises.make(expire, resolve, fulfill, reject);

        vm.warp(block.timestamp + 30 days + 1);

        vm.expectRevert(Forbidden.selector);
        promises.fulfill(1);
    }

    function test_fulfill_promise_sets_state_resolved_when_promise_resolves()
        public
    {
        uint64 expire = uint64(block.timestamp) + 30 days;
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, (true))
        });
        Call memory fulfill = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        Call memory reject = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        promises.make(expire, resolve, fulfill, reject);

        promises.fulfill(1);

        Promise memory updated = promises.promises(1);
        assertEq(uint8(updated.state), uint8(State.Resolved));
    }

    function test_fulfill_promise_reverts_unauthorized_caller() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, (true))
        });
        Call memory fulfill = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        Call memory reject = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        promises.make(expire, resolve, fulfill, reject);

        vm.expectRevert(Forbidden.selector);
        vm.prank(eve);
        promises.fulfill(1);
    }

    function test_fulfill_promise_reverts_already_resolved() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, (true))
        });
        Call memory fulfill = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        Call memory reject = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        promises.make(expire, resolve, fulfill, reject);

        promises.fulfill(1);

        vm.expectRevert(Resolved.selector);
        promises.fulfill(1);
    }

    function test_fulfill_promise_calls_fulfill_target_when_promise_resolves()
        public
    {
        uint64 expire = uint64(block.timestamp) + 30 days;
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, (true))
        });
        Call memory fulfill = Call({
            target: address(fulfillTarget),
            callData: abi.encodeCall(fulfillTarget.fulfill, ())
        });
        Call memory reject = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        promises.make(expire, resolve, fulfill, reject);

        assertEq(fulfillTarget.called(), false);

        promises.fulfill(1);

        assertEq(fulfillTarget.called(), true);
    }

    function test_reject_promise_reverts_unauthorized_rejecter() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, (false))
        });
        Call memory fulfill = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        Call memory reject = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        promises.make(expire, resolve, fulfill, reject);

        vm.expectRevert(Forbidden.selector);
        vm.prank(eve);
        promises.reject(1);
    }

    function test_reject_promise_sets_state_rejected_when_promise_rejects()
        public
    {
        uint64 expire = uint64(block.timestamp) + 30 days;
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, (false))
        });
        Call memory fulfill = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        Call memory reject = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        promises.make(expire, resolve, fulfill, reject);

        vm.warp(block.timestamp + 30 days + 1);

        promises.reject(1);

        Promise memory updated = promises.promises(1);
        assertEq(uint8(updated.state), uint8(State.Rejected));
    }

    function test_reject_promise_calls_reject_target_when_promise_rejects()
        public
    {
        uint64 expire = uint64(block.timestamp) + 30 days;
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, (false))
        });
        Call memory fulfill = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        Call memory reject = Call({
            target: address(rejectTarget),
            callData: abi.encodeCall(rejectTarget.reject, ())
        });
        promises.make(expire, resolve, fulfill, reject);

        vm.warp(block.timestamp + 30 days + 1);

        assertEq(rejectTarget.called(), false);

        promises.reject(1);

        assertEq(rejectTarget.called(), true);
    }

    function test_unauthorized_caller_cannot_call_proxy() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        Call memory resolve = Call({
            target: address(resolver),
            callData: abi.encodeCall(resolver.resolve, (true))
        });
        Call memory fulfill = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        Call memory reject = Call({
            target: address(noop),
            callData: abi.encodeCall(noop.noop, ())
        });
        promises.make(expire, resolve, fulfill, reject);

        assertEq(promises.proxy(1).promises(), address(promises));

        PromiseProxy proxy = promises.proxy(1);

        vm.expectRevert(Forbidden.selector);
        vm.prank(eve);
        proxy.exec(fulfill.target, fulfill.callData);
    }
}
