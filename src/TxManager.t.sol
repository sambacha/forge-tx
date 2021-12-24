pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/base.sol";
import './TxManager.sol';

contract Tester {
    ERC20 public token;
    uint256 public value;

    constructor(ERC20 token_) public {
        token = token_;
    }

    function ok(uint256 value_) public {
        value = value_;
    }

    function balance() public {
        value = token.balanceOf(msg.sender);
    }

    function fail() public {
        revert();
    }
}

// EtherToken from 0x does not throw/revert on failed transfers as most of other tokens.
// <https://etherscan.io/address/0x2956356cd2a2bf3202f771f50d3d14a367b48070#code>
//
// This tiny contract tries to replicate this behaviour so we can test against it.
// Every `transfer`/`transferFrom` fails, but there is no throw/revert.
// Instead of it, `false` gets returned from these functions.
contract NotThrowingToken {
    uint256                                            _supply;
    mapping (address => uint256)                       _balances;
    mapping (address => mapping (address => uint256))  _approvals;

    event Transfer( address indexed from, address indexed to, uint value);
    event Approval( address indexed owner, address indexed spender, uint value);

    constructor(uint supply) public {
        _balances[msg.sender] = supply;
        _supply = supply;
    }

    function totalSupply() public view returns (uint) {
        return _supply;
    }
    function balanceOf(address src) public view returns (uint) {
        return _balances[src];
    }
    function allowance(address src, address guy) public view returns (uint) {
        return _approvals[src][guy];
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return false;
    }

    function transferFrom(address src, address dst, uint wad) public returns (bool) {
        return false;
    }

    function approve(address guy, uint wad) public returns (bool) {
        _approvals[msg.sender][guy] = wad;

        emit Approval(msg.sender, guy, wad);

        return true;
    }
}

contract TxManagerTest is DSTest {
    TxManager        txManager;
    DSTokenBase      token1;
    DSTokenBase      token2;
    NotThrowingToken token3;
    Tester           tester1;
    Tester           tester2;

    function setUp() public {
        txManager = new TxManager();
        token1 = new DSTokenBase(1000000);
        token2 = new DSTokenBase(2000000);
        token3 = new NotThrowingToken(3000000);
        tester1 = new Tester(token1);
        tester2 = new Tester(token2);
    }

    function testNoTokensNoCalls() public {
        txManager.execute(new address[](0), new bytes(0));
    }

    function testNoTokensOneCall() public {
        assertEq(tester1.value(), 0);
        assertEq(tester2.value(), 0);

        // seth calldata 'ok(uint256)' 10
        bytes memory data = "\x80\x97\x2a\x7d\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0a";

        bytes memory call = concat(concat(addressToBytes(address(tester1)), uintToBytes(data.length)), data);

        txManager.execute(new address[](0), call);

        assertEq(tester1.value(), 10);
        assertEq(tester2.value(), 0);
    }

    function testNoTokensTwoCalls() public {
        assertEq(tester1.value(), 0);
        assertEq(tester2.value(), 0);

        // seth calldata 'ok(uint256)' 10
        bytes memory data1 = "\x80\x97\x2a\x7d\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0a";
        bytes memory call1 = concat(concat(addressToBytes(address(tester1)), uintToBytes(data1.length)), data1);

        // seth calldata 'ok(uint256)' 13
        bytes memory data2 = "\x80\x97\x2a\x7d\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0d";
        bytes memory call2 = concat(concat(addressToBytes(address(tester2)), uintToBytes(data2.length)), data2);

        txManager.execute(new address[](0), concat(call1, call2));

        assertEq(tester1.value(), 10);
        assertEq(tester2.value(), 13);
    }

    function testFailOnFailedTransfer() public {
        txManager.execute(tokens(address(token3)), new bytes(0));
    }

    function testFailOnFailedCall() public {
        // seth calldata 'fail()'
        bytes memory data = "\xa9\xcc\x47\x18";
        bytes memory call = concat(concat(addressToBytes(address(tester1)), uintToBytes(data.length)), data);

        txManager.execute(new address[](0), call);
    }

    function testNoTokenTransferIfNotApproved() public {
        // seth calldata 'balance()'
        bytes memory data = "\xb6\x9e\xf8\xa8";
        bytes memory call = concat(concat(addressToBytes(address(tester1)), uintToBytes(data.length)), data);

        txManager.execute(tokens(address(token1)), call);

        assertEq(tester1.value(), 0);
    }

    function testTransferTokenAllowanceAndReturnFunds() public {
        // seth calldata 'balance()'
        bytes memory data = "\xb6\x9e\xf8\xa8";
        bytes memory scriptData = concat(concat(addressToBytes(address(tester1)), uintToBytes(data.length)), data);

        token1.approve(address(txManager), 1000);
        txManager.execute(tokens(address(token1)), scriptData);

        assertEq(tester1.value(), 1000);
        assertEq(token1.balanceOf(address(this)), 1000000);
    }

    function testTransferNoMoreThanTokenBalance() public {
        // seth calldata 'balance()'
        bytes memory data = "\xb6\x9e\xf8\xa8";
        bytes memory call = concat(concat(addressToBytes(address(tester1)), uintToBytes(data.length)), data);

        token1.approve(address(txManager), 1000000000000);
        txManager.execute(tokens(address(token1)), call);

        assertEq(tester1.value(), 1000000);
    }

    function testTransferTwoTokensAndReturnFunds() public {
        // seth calldata 'balance()'
        bytes memory data1 = "\xb6\x9e\xf8\xa8";
        bytes memory call1 = concat(concat(addressToBytes(address(tester1)), uintToBytes(data1.length)), data1);
        // seth calldata 'balance()'
        bytes memory data2 = "\xb6\x9e\xf8\xa8";
        bytes memory call2 = concat(concat(addressToBytes(address(tester2)), uintToBytes(data2.length)), data2);

        token1.approve(address(txManager), 1000);
        token2.approve(address(txManager), 1500);
        txManager.execute(tokens(address(token1), address(token2)), concat(call1, call2));

        assertEq(tester1.value(), 1000);
        assertEq(tester2.value(), 1500);

        // check if funds returned after calls have been made
        assertEq(token1.balanceOf(address(this)), 1000000);
        assertEq(token2.balanceOf(address(this)), 2000000);
    }

    // --- --- ---

    function uintToBytes(uint256 x) internal returns (bytes memory b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }

    function addressToBytes(address a) internal view returns (bytes memory b) {
       assembly {
            let m := mload(0x40)
            mstore(add(m, 20), xor(0x140000000000000000000000000000000000000000, a))
            mstore(0x40, add(m, 52))
            b := m
       }
    }

    function concat(
        bytes memory _preBytes,
        bytes memory _postBytes
    )
        internal
        pure
        returns (bytes memory)
    {
        bytes memory tempBytes;

        assembly {
            // Get a location of some free memory and store it in tempBytes as
            // Solidity does for memory variables.
            tempBytes := mload(0x40)

            // Store the length of the first bytes array at the beginning of
            // the memory for tempBytes.
            let length := mload(_preBytes)
            mstore(tempBytes, length)

            // Maintain a memory counter for the current write location in the
            // temp bytes array by adding the 32 bytes for the array length to
            // the starting location.
            let mc := add(tempBytes, 0x20)
            // Stop copying when the memory counter reaches the length of the
            // first bytes array.
            let end := add(mc, length)

            for {
                // Initialize a copy counter to the start of the _preBytes data,
                // 32 bytes into its memory.
                let cc := add(_preBytes, 0x20)
            } lt(mc, end) {
                // Increase both counters by 32 bytes each iteration.
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                // Write the _preBytes data into the tempBytes memory 32 bytes
                // at a time.
                mstore(mc, mload(cc))
            }

            // Add the length of _postBytes to the current length of tempBytes
            // and store it as the new length in the first 32 bytes of the
            // tempBytes memory.
            length := mload(_postBytes)
            mstore(tempBytes, add(length, mload(tempBytes)))

            // Move the memory counter back from a multiple of 0x20 to the
            // actual end of the _preBytes data.
            mc := end
            // Stop copying when the memory counter reaches the new combined
            // length of the arrays.
            end := add(mc, length)

            for {
                let cc := add(_postBytes, 0x20)
            } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                mstore(mc, mload(cc))
            }

            // Update the free-memory pointer by padding our last write location
            // to 32 bytes: add 31 bytes to the end of tempBytes to move to the
            // next 32 byte block, then round down to the nearest multiple of
            // 32. If the sum of the length of the two arrays is zero then add
            // one before rounding down to leave a blank 32 bytes (the length block with 0).
            mstore(0x40, and(
              add(add(end, iszero(add(length, mload(_preBytes)))), 31),
              not(31) // Round down to the nearest 32 bytes.
            ))
        }

        return tempBytes;
    }

    function tokens(address a1) public returns (address[] memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = a1;
        return tokens;
    }

    function tokens(address a1, address a2) public returns (address[] memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = a1;
        tokens[1] = a2;
        return tokens;
    }
}
