// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC721} from "solmate/tokens/ERC721.sol";

enum State {
    Pending,
    Resolved,
    Rejected
}

struct Call {
    address target;
    bytes callData;
}

struct Promise {
    uint64 expires;
    Call resolve;
    Call fulfill;
    Call reject;
    State state;
}

error Forbidden();
error NotFound();
error Resolved();
error CallFailed();

contract Promises is ERC721("Promises", "PROMISE") {
    mapping(uint256 => Promise) internal _promises;
    uint256 public count;

    event Fulfilled(address indexed caller, uint256 promiseId);
    event Rejected(address indexed caller, uint256 promiseId);

    function make(
        uint64 expires,
        Call calldata resolve,
        Call calldata _fulfill,
        Call calldata _reject
    ) external returns (address) {
        _promises[++count] = Promise({
            expires: expires,
            resolve: resolve,
            fulfill: _fulfill,
            reject: _reject,
            state: State.Pending
        });
        PromiseProxy _proxy = new PromiseProxy{ salt: bytes32(count) }();
        _mint(msg.sender, count);
        _mint(msg.sender, count + 1);
        return address(_proxy);
    }

    function fulfill(uint256 promiseId)
        external
        returns (bytes memory result)
    {
        // Promise must exist
        Promise memory _promise = _promises[promiseId];
        if (_promise.expires == 0) revert NotFound();

        // Promise cannot already be resolved
        if (_promise.state != State.Pending) revert Resolved();

        // Promise must not be expired
        if (block.timestamp > _promise.expires) revert Forbidden();

        // Caller must own fulfill token
        if (msg.sender != ownerOf(2 * promiseId - 1)) revert Forbidden();

        // Call resolver
        bool success;
        (success, result) =
            address(_promise.resolve.target).call(_promise.resolve.callData);
        (bool resolved) = abi.decode(result, (bool));

        if (success && resolved) {
            _promises[promiseId].state = State.Resolved;
            (success, result) = proxy(promiseId).exec(
                _promise.fulfill.target, _promise.fulfill.callData
            );
            emit Fulfilled(msg.sender, promiseId);
            if (!success) revert CallFailed();
        } else {
            revert Forbidden();
        }
    }

    function reject(uint256 promiseId) external returns (bytes memory result) {
        // Promise must exist
        Promise memory _promise = _promises[promiseId];
        if (_promise.expires == 0) revert NotFound();

        // Promise cannot already be resolved
        if (_promise.state != State.Pending) revert Resolved();

        // Promise must be expired
        if (block.timestamp <= _promise.expires) revert Forbidden();

        // Caller must own reject token
        if (msg.sender != ownerOf(2 * promiseId)) revert Forbidden();

        bool success;
        _promises[promiseId].state = State.Rejected;
        (success, result) = proxy(promiseId).exec(
            _promise.reject.target, _promise.reject.callData
        );
        emit Rejected(msg.sender, promiseId);
        if (!success) revert CallFailed();
    }

    function proxy(uint256 promiseId) public view returns (PromiseProxy) {
        return PromiseProxy(
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                address(this),
                                promiseId,
                                keccak256(type(PromiseProxy).creationCode)
                            )
                        )
                    )
                )
            )
        );
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    function totalSupply() external view returns (uint256) {
        return count * 2;
    }

    function promises(uint256 promiseId)
        external
        view
        returns (Promise memory)
    {
        return _promises[promiseId];
    }
}

contract PromiseProxy {
    address public immutable promises;

    constructor() {
        promises = msg.sender;
    }

    function exec(address target, bytes memory callData)
        external
        returns (bool success, bytes memory result)
    {
        if (msg.sender != promises) revert Forbidden();
        (success, result) = target.call(callData);
    }
}
