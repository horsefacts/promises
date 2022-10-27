# promises

![Build Status](https://github.com/horsefacts/promises/actions/workflows/.github/workflows/test.yml/badge.svg?branch=main)

## Promises — generic tokenized commitments

### External functions:

- `make`: Make a promise. Issues separate fulfill and reject ERC721 tokens to caller.
  - `callable`: Whether the promise may be resolved `Before` or `After` its `timestamp`.
  - `timestamp`: Time at which the promise either expires or can be resolved.
  - `resolve`: Target address and calldata for a call that will be invoked to decide whether the promise is fulfilled or rejected. This call should return a `bool`.
  - `fulfill`: A call that will be invoked if the promise is fulfilled.
  - `reject`: A call that will be invoked if the promise is rejected.
- `keep`: Keep a promise. Invokes `fulfill` if `resolve` returns `true`, otherwise invokes `reject`. Caller must own the fulfill token to fulfill, or the reject token to reject.
- `ERC721` external interface.

### View functions:

- `proxy(uint256)`: Get a promise's execution proxy by promise ID.
- `promises(uint256)`: Get a promise by ID.
- `ERC721` view interface.
