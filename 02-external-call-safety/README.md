# External calls safety

## Overview

Many issues are related to external calls (one of the most common issues with oracle manipulation); e.g. reentrancy, DoS, return values, gas...

### Reentrancy

1.  Typical reentrancy...

2.  **Cross-function** reentrancy, when the reentrant call is made to another function of the same contract. Typically, when a sensitive function _does_ have a `nonReentrant` modifier, yet during the external call, the attacker reenters the contract through an unprotected function, which performs operations using the now outdated state.

3.  **Cross-contract** reentrancy, when the reentrant call is made to another contract, since the reentrancy guard is only effective within the same contract.

4.  [**Read-only** reentrancy](https://officercia.mirror.xyz/DBzFiDuxmDOTQEbfXhvLdK0DXVpKu1Nkurk0Cqk3QKc), when exploiting the "in-between" states of a contracts by making reentrant calls in the same transaction, that only read the state of the contract without modifying it. Essentially, it's just like cross-contract reentrancy, except that the reentered contract is usually from a third party.

        - e.g:
        1. an attacker calls a (nonreentrant or not) function that performs some operations, then makes the external call, then updates the state;
        2. when it hands over the execution to the attacker contract (so before updating the state), the attacker might not be able to take advantage of this to enter the same function, another one, or even another contract;
        3. however, they might be able to perform _anything_ on systems that build on top of this one—whether it's some complex interaction, or even just that they read the (already outdated) state through a view function;
        4. at this point, the only limit for the exploit is the gas consumption...

Notice that some tokens implement a `on<x>Received` callback if the receiver is a contract, which makes them vulnerable to reentrancy. Among others, this is the case for `ERC721`, `ERC777`, `ERC1155`, or `ERC-677` tokens (basically ERC20 but with a `transferAndCall` function that triggers a `onTokenTransfer` callback).

### DoS

Generally, when making an external call, can it fail? What happens if it does? Can it be exploited? For instance, on a callback that happens during an operation in the system.

    - e.g. during a liquidation: if it is implemented maliciously (or even just incorrectly), it can make the transaction revert, or just behave unexpectedly—what happens there?
    - e.g. cont. if the caller is a contract that doesn't accept ETH, what happens, and what is the alternative?

### Return values

There are different possible issues based on how extensively the values are checked:

- Are all possible values checked?
- Does it handle the case where it returns unexpected bytes? Can the user provide arbitrary bytes?
  - if these bytes are returned from an untrusted contract, you can never expect it to be actually bytes as it was intended.

### Gas

When calling an external function without specifying the amount of gas, it will forward all the remaining gas.

- This can especially be problematic in the case of meta-transactions (gasless transactions), as it can be exploited to drain the relayer.

It's also good to point out that gas consumption can be arbitrarily manipulated in the case of return data. Take the example of a `try`/`catch` block that would copy the return data into memory, such as `catch (bytes memory lowLevelData) { ... }`: this alone is already an issue, as just copying the return data—which can be arbitrarily long—will consume a significant amount of gas. This can be used to make the transaction fail at will and game the system.

    e.g. someone could saturate the return data to have the transaction cost more than the block gas limit, which would make the order fail; however, they could as well make it be processed in a later block, when the market conditions are actually different than when the order was placed.

## Strategies

### Reentrancy

1. CEI (Checks/Effects/Interactions) if it's possible;
2. if some state updates need to be done before the external call, use a [reentrancy guard](https://docs.openzeppelin.com/contracts/4.x/api/security#ReentrancyGuard);
3. also see the [FREI-PI pattern](https://www.nascent.xyz/idea/youre-writing-require-statements-wrong) (Function-Requirements/Effects/Interactions/Protocol-Invariants) for a more exhaustive approach, that considers the whole contract when performing checks.

   - It is also a good practice to keep the global system in mind when writing a smart contract. (Sometimes it's also referred as pre/post conditions or hoare triple—more about this in the [additional resources](#additional-resources) section).
   - Essentially the idea is to **enforce the system's invariants** (e.g. the system should always be solvent) by making sure that the contract's state is always consistent with the system's state—after virtually every state-modifying function call.

The other cases of reentrancy (cross-contract/read-only) are a bit more tricky to handle, as they requires a more thorough analysis of the system, and even third parties. Some potential cases can be detected with static analysis tools (e.g. Slither enriched with [Slitherin detectors](https://github.com/pessimistic-io/slitherin)).

Basically, to take care of reentrancy, you should always **consider the system as a whole**, including all functions (and even view functions). Meaning also considering the possible vulnerabilities if the system is implemented somewhere else—another protocol building on top of this one.

There are ways to securely handle external calls, even to a completely arbitrary contract, up to cross-contract reentrancy. For this to work, the auditor should obviously verify the execution flow _after_ the callback with extra consideration (see invariant checks, post-conditions, etc.) and take care of read-only reentrancy as well. A contract such as a `GlobalReentrancyGuard`, as done in GMX V2, can be used to handle cross-contract reentrancy; simply by using a global data store to keep track of the reentrancy status _for all contracts_.

```solidity
// GlobalReentrancyGuard.sol
// All contracts in the system can inherit this one to use the shared reentrancy guard.

modifier globalNonReentrant() {
  _nonReentrantBefore();
  _;
  _nonReentrantAfter();
}

function _nonReentrantBefore() private {
  uint256 status = dataStore.getUint256("reentrancyStatus");
  if (status == ENTERED) {
    revert("ReentrancyGuard: reentrant call");
  }
  dataStore.setUint256("reentrancyStatus", ENTERED);
}
```

As a more general and exhaustive approach, the ideal way is to update _all_ the state of the system _before_ the external call, this way it is already consistent at the time of the callback.

As an auditor, a suggested process for veryfing this is the following:

1. make a list of _all_ the external calls in the system;
2. for each of them, list any piece of state that is outdated at the time of the external call;
3. make a list of all external calls that can be made during the callback (basically any user-accessible function)—the surface of the system;
4. think of any advantage that can be taken of the outdated state of any data listed in 2. during the execution of any function listed in 3.

### DoS

Generally, it's a good practice to make sure that the target contract is trusted. In any case, any failure should be handled in a way that doesn't break the system—meaning that it should not leave the system in an inconsistent state, and an alternative should be available to recover from it.

The concepts of FREI-PI/post-conditions can also be applied here, to make sure invariants are always enforced after the external call, thus preventing a DoS.

### Return values

Any value that is returned from an external call should be explicitely checked, especially if the external source is not trusted. The same is true for bytes, as they can actually take any form in this case.

    - e.g. when trying to decode a string from bytes, it should be checked that the bytes are actually a string.

Having the external contract "trusted" is never a guarantee and an excuse for bypassing these checks. It should at least be considered a centralization risk, if the owner/administrator considers it not an issue as they "control" the data that is returned.

### Gas

Basically, if the external contract is not trusted, it should be called with a limited amount of gas.

An example of calling an arbitraty contract to send ETH and capture the success status, while explicitly not copying any return data and limiting the amount of gas:

```solidity
bool success;

assembly {
  success := call(
    gasLimit,
    targetAddress,
    amount,
    0, // in: input data
    0, // insize: input data length
    0, // out: output data
    0 // outsize: output data length
  )
}
```

## Additional resources

- [Dave Nicolette, Design By Contract: Part One, 2018-05-07](https://www.leadingagile.com/2018/05/design-by-contract-part-one/)

- [Dave Nicolette, Design By Contract: Part Two, 2018-05-08](https://www.leadingagile.com/2018/05/design-by-contract-part-two/)

- [Wikipedia, Hoare logic](https://en.wikipedia.org/wiki/Hoare_logic)

```

```
