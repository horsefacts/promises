// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Promises.sol";

contract Calls {
    bool public fulfillCalled;
    bool public rejectCalled;

    function setFulfillCalled() external {
        fulfillCalled = true;
    }

    function setRejectCalled() external {
        rejectCalled = true;
    }
}
contract ResolveTrue is IResolve{

    function resolve() external pure returns (bool) {
        return true;
    }

}

contract ResolveFalse is IResolve{

    function resolve() external pure returns (bool) {
        return false;
    }

}

contract Fulfill is IFulfill {
    Calls public immutable calls = new Calls();

    function fulfill(address,address) external {
        calls.setFulfillCalled();
    }
}

contract Reject is  IReject {
    Calls public immutable calls = new Calls();

    function reject(address,address) external {
        calls.setRejectCalled();
    }
}

contract PromisesTest is Test {
    Promises public promises;

    ResolveTrue public resolveTrue;
    ResolveFalse public resolveFalse;
    Fulfill public fulfill;
    Reject public reject;

    address eve = makeAddr("eve");

    function setUp() public {
        promises = new Promises();
        resolveTrue = new ResolveTrue();
        resolveFalse = new ResolveFalse();
        fulfill = new Fulfill();
        reject = new Reject();
    }

    function test_make_stores_promise() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        promises.make(expire, resolveTrue, fulfill, reject);

        assertEq(promises.count(), 1);

        Promise memory created = promises.promises(1);
        assertEq(uint8(created.state), uint8(State.Pending));
        assertEq(created.expires, expire);

        assertEq(address(created.resolve), address(resolveTrue));
        assertEq(address(created.fulfill), address(fulfill));
        assertEq(address(created.reject), address(reject));
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
        promises.make(expire, resolveTrue, fulfill, reject);

        vm.warp(block.timestamp + 30 days + 1);

        vm.expectRevert(Forbidden.selector);
        promises.fulfill(1);
    }

    function test_fulfill_promise_sets_state_resolved_when_promise_resolves()
        public
    {
        uint64 expire = uint64(block.timestamp) + 30 days;
        promises.make(expire, resolveTrue, fulfill, reject);

        promises.fulfill(1);

        Promise memory updated = promises.promises(1);
        assertEq(uint8(updated.state), uint8(State.Resolved));
    }

    function test_fulfill_promise_reverts_unauthorized_caller() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        promises.make(expire, resolveTrue, fulfill, reject);

        vm.expectRevert(Forbidden.selector);
        vm.prank(eve);
        promises.fulfill(1);
    }

    function test_fulfill_promise_reverts_already_resolved() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        promises.make(expire, resolveTrue, fulfill, reject);

        promises.fulfill(1);

        vm.expectRevert(Resolved.selector);
        promises.fulfill(1);
    }

    function test_fulfill_promise_calls_fulfill_target_when_promise_resolves()
        public
    {
        uint64 expire = uint64(block.timestamp) + 30 days;
        promises.make(expire, resolveTrue, fulfill, reject);

        assertEq(fulfill.calls().fulfillCalled(), false);

        promises.fulfill(1);

        assertEq(fulfill.calls().fulfillCalled(), true);
    }

    function test_reject_promise_reverts_unauthorized_rejecter() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        promises.make(expire, resolveFalse, fulfill, reject);

        vm.expectRevert(Forbidden.selector);
        vm.prank(eve);
        promises.reject(1);
    }

    function test_reject_promise_sets_state_rejected_when_promise_rejects()
        public
    {
        uint64 expire = uint64(block.timestamp) + 30 days;
        promises.make(expire, resolveFalse, fulfill, reject);

        vm.warp(block.timestamp + 30 days + 1);

        promises.reject(1);

        Promise memory updated = promises.promises(1);
        assertEq(uint8(updated.state), uint8(State.Rejected));
    }

    function test_reject_promise_calls_reject_target_when_promise_rejects()
        public
    {
        uint64 expire = uint64(block.timestamp) + 30 days;
        promises.make(expire, resolveFalse, fulfill, reject);

        vm.warp(block.timestamp + 30 days + 1);

        assertEq(reject.calls().rejectCalled(), false);

        promises.reject(1);

        assertEq(reject.calls().rejectCalled(), true);
    }

    function test_unauthorized_caller_cannot_call_proxy() public {
        uint64 expire = uint64(block.timestamp) + 30 days;
        promises.make(expire, resolveFalse, fulfill, reject);

        assertEq(promises.proxy(1).promises(), address(promises));

        PromiseProxy proxy = promises.proxy(1);

        vm.expectRevert(Forbidden.selector);
        vm.prank(eve);
        proxy.exec(address(fulfill), abi.encodeCall(fulfill.fulfill, (eve, address(0))));
    }
}
