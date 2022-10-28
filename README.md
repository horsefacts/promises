# promises

![Build Status](https://github.com/horsefacts/promises/actions/workflows/.github/workflows/test.yml/badge.svg?branch=main)

## Promises — generic tokenized commitments

### External functions:

- `make`: Make a promise. Issues separate long/fulfill and short/reject ERC721 tokens to caller.
  - `expiration`: Time at which the promise expires and can be rejected.
  - `resolve`: A contract that implements `IResolve`. `resolve.resolve()` will be invoked to decide whether the promise can be fulfilled. This call should return a `bool`.
  - `fulfill`: A contract that implements `IFulfill`. `fulfill.fulfill(address long, address short)` will be invoked if the promise is fulfilled. This may be the same contract as `fulfill` as long as it implements the interface.
  - `reject`: A contract that implements `IReject`. `reject.reject(address long, address short)` will be invoked if the promise is rejected. This may be the same contract as `fulfill` and `reject` as long as it implements all three interfaces.
- `fulfill`: Fulfill a promise. Invokes `fulfill` if `resolve` returns `true`. Promise must not be expired. Caller must own the long/fulfill token.
- `reject`: Reject a promise. Invokes `reject`. Promise must be expired. Caller must own the short/reject token.
- `ERC721` external interface.

### View functions:

- `proxy(uint256)`: Get a promise's execution proxy by promise ID.
- `promises(uint256)`: Get a promise by ID.
- `ERC721` view interface.
