# External calls safety

## Overview

- Many issues are related to external calls (one of the most common issues with oracle manipulation); e.g. reentrancy, DoS, return values, gas...

### Reentrancy

- Read-only reentrancy, when exploiting the "in-between" states of a contracts by making reentrant calls in the same transaction, that only read the state of the contract without modifying it.

  - It can happen even if one of the contracts has a reentrancy guard, if the other is called in the same transaction.

## Strategies

### Reentrancy

1. CEI (Checks/Effects/Interactions) if it's possible;
2. if some state updates need to be done before the external call, use a [reentrancy guard](https://docs.openzeppelin.com/contracts/4.x/api/security#ReentrancyGuard);
3. also see the [FREI-PI pattern](https://www.nascent.xyz/idea/youre-writing-require-statements-wrong) (Function-Requirements/Effects/Interactions/Protocol-Invariants) for a more exhaustive approach, that considers the whole contract when performing checks.

   - It is also a good practice to keep the global system in mind when writing a smart contract. (Sometimes it's also referred as pre/post conditions or hoare triple—more about this in the [additional resources](#additional-resources) section).

## Additional resources

- [Dave Nicolette, Design By Contract: Part One, 2018-05-07](https://www.leadingagile.com/2018/05/design-by-contract-part-one/)

- [Dave Nicolette, Design By Contract: Part Two, 2018-05-08](https://www.leadingagile.com/2018/05/design-by-contract-part-two/)

- [Wikipedia, Hoare logic](https://en.wikipedia.org/wiki/Hoare_logic)
