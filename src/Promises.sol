// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC721} from "solmate/tokens/ERC721.sol";

interface IResolve {
    function resolve() external view returns (bool);
}

interface IFulfill {
    function fulfill(address long, address short) external;
}

interface IReject {
    function reject(address long, address short) external;
}

enum State {
    Pending,
    Resolved,
    Rejected
}

struct Promise {
    uint64 expires;
    IResolve resolve;
    IFulfill fulfill;
    IReject reject;
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
        address execute
    ) external returns (address) {
        return make(expires, IResolve(execute), IFulfill(execute), IReject(execute));
    }

    function make(
        uint64 expires,
        IResolve resolve,
        IFulfill _fulfill,
        IReject _reject
    ) public returns (address) {
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

        // Get proxy
        PromiseProxy _proxy = proxy(promiseId);

        // Call resolver
        (bool success, bytes memory result) = _proxy.exec(address(_promise.resolve), abi.encodeCall(IResolve.resolve, ()));
        (bool resolved) = abi.decode(result, (bool));

        if (success && resolved) {
            address short = ownerOf(2 * promiseId);
            _promises[promiseId].state = State.Resolved;
            (success,) = _proxy.exec(address(_promise.fulfill), abi.encodeCall(IFulfill.fulfill, (msg.sender, short)));
            if(!success) revert CallFailed();
            emit Fulfilled(msg.sender, promiseId);
        } else {
            revert Forbidden();
        }
    }

    function reject(uint256 promiseId) external {
        // Promise must exist
        Promise memory _promise = _promises[promiseId];
        if (_promise.expires == 0) revert NotFound();

        // Promise cannot already be resolved
        if (_promise.state != State.Pending) revert Resolved();

        // Promise must be expired
        if (block.timestamp <= _promise.expires) revert Forbidden();

        // Caller must own reject token
        if (msg.sender != ownerOf(2 * promiseId)) revert Forbidden();

        // Get proxy
        PromiseProxy _proxy = proxy(promiseId);

        address long = ownerOf(2 * promiseId - 1);
        _promises[promiseId].state = State.Rejected;
        (bool success,) = _proxy.exec(address(_promise.reject), abi.encodeCall(IReject.reject, (long, msg.sender)));
        if(!success) revert CallFailed();
        emit Rejected(msg.sender, promiseId);
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
        (success, result) = target.delegatecall(callData);
    }
}
