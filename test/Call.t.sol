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

contract NFT is ERC721("Nonfungible Token", "NFT") {
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}

contract CallOption is IResolve, IFulfill, IReject {
    Token public immutable token;
    NFT public immutable nft;

    constructor(Token _token, NFT _nft) {
        token = _token;
        nft = _nft;
    }

    // The resolve function always returns true, since
    // the long side of the option may exercise any
    // time before expiration.
    function resolve() external pure returns (bool) {
        return true;
    }

    // If the long side chooses to exercise the option, send
    // the long address the escrowed NFT. Long must transfer
    // 1000 tokens to short or the call will revert.
    function fulfill(address long, address short) external {
        nft.transferFrom(address(this), long, 1);
        token.transferFrom(long, short, 1000 ether);
    }

    // If the long side chooses not to exercise the option before
    // it expires, the short may withdraw their escrowed token.
    function reject(address, address short) external {
        nft.transferFrom(address(this), short, 1);
    }
}

contract CallTest is Test {
    Promises public promises;
    Token public token;
    NFT public nft;
    CallOption public callOption;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address dave = makeAddr("dave");

    function setUp() public {
        promises = new Promises();
        token = new Token();
        nft = new NFT();
        callOption = new CallOption(token, nft);

        nft.mint(alice, 1);
        token.mint(bob, 1000 ether);
    }

    function set_up_call() public {
        // Alice writes a call option on her NFT.

        // Promise expiration is 30 days from now.
        uint64 expire = uint64(block.timestamp) + 30 days;

        vm.startPrank(alice);
        promises.make(expire, address(callOption));
        PromiseProxy proxy = promises.proxy(1);

        // Alice sends her NFT to the promise proxy.
        nft.transferFrom(alice, address(proxy), 1);

        // Alice's nft balance is now zero
        assertEq(nft.balanceOf(alice), 0);

        // Promise proxy is owner of token
        assertEq(nft.ownerOf(1), address(proxy));

        // Alice sends the long token to Bob.
        promises.transferFrom(alice, bob, 1);

        vm.stopPrank();
    }

    function test_bob_exercises() public {
        set_up_call();

        PromiseProxy proxy = promises.proxy(1);

        vm.startPrank(bob);
        token.approve(address(proxy), 1000 ether);
        promises.fulfill(1);
        vm.stopPrank();

        // Tokens are transferred to Alice
        assertEq(token.balanceOf(alice), 1000 ether);

        // NFT is transferred to Bob
        assertEq(nft.ownerOf(1), bob);
    }

    function test_option_expires() public {
        set_up_call();

        // Warp beyond expiration
        vm.warp(block.timestamp + 30 days + 1);

        // Bob cannot exercise
        vm.prank(bob);
        vm.expectRevert(Forbidden.selector);
        promises.fulfill(1);

        // Alice can reject and withdraw the NFT
        vm.prank(alice);
        promises.reject(1);

        // NFT is transferred back to Alice
        assertEq(nft.ownerOf(1), alice);
    }

    function test_bob_transfers_long() public {
        set_up_call();
        token.mint(dave, 1000 ether);

        PromiseProxy proxy = promises.proxy(1);

        // Bob transfers his long/fulfill token to Dave.
        // Now Dave owns the option and may choose to
        // buy Alice's NFT for 1000 tokens before expiration.
        vm.prank(bob);
        promises.transferFrom(bob, dave, 1);

        assertEq(promises.ownerOf(1), dave);

        // Since Bob no longer owns the fulfill token,
        // he cannot exercise.
        vm.prank(bob);
        vm.expectRevert(Forbidden.selector);
        promises.fulfill(1);

        vm.startPrank(dave);
        token.approve(address(proxy), 1000 ether);
        promises.fulfill(1);
        vm.stopPrank();

        // Tokens are transferred to Alice
        assertEq(token.balanceOf(alice), 1000 ether);

        // NFT is transferred to Dave
        assertEq(nft.ownerOf(1), dave);
    }

    function test_alice_transfers_short() public {
        set_up_call();

        // Alice tranfers her short/reject token to Carol
        vm.prank(alice);
        promises.transferFrom(alice, carol, 2);

        // Warp beyond expiration
        vm.warp(block.timestamp + 30 days + 1);

        // Alice cannot reject
        vm.prank(alice);
        vm.expectRevert(Forbidden.selector);
        promises.fulfill(1);

        // Carol can reject and withdraw the NFT
        vm.prank(carol);
        promises.reject(1);

        // NFT is transferred to Carol
        assertEq(nft.ownerOf(1), carol);
    }
}
