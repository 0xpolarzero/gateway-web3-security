# Principles of smart contract testing

_These are a mix of principles described by Owen and my own additional observations._

## Basics

1. Unit tests: catching bugs early on.

2. Integration tests: chatching bugs at the composability level (meaning the system as a whole).

- 100% coverage is some kind of prerequisite, but definitely far from enough.

The idea is that this covers only the surface, when we actually want to cover the whole _volume_.

## Path dependence/independence

- **Path independant** interaction: the outcome is the same regardless of the order of the calls.
  ```solidity
  IERC20(token).transferFrom(address(ALICE), address(this), amount);
  IERC20(token).transferFrom(address(BOB), address(this), amount);
  ```
- **Path dependant** interaction: the outcome depends on the order of the calls.
  ```solidity
  // Alice swaps 1 ETH for 2,000 USDC on an Uniswap pool
  // Bob swaps 1 ETH for x USDC on an Uniswap pool; x will be lower since the first swap impacted the price
  ```

Basically, limiting tests to path independant interactions will really miss out on a lot of the volume; the more path independant tests, the greater the volume "coverage".

## Fuzzing

Fuzzing is a good method to fill out the "testing volume" for a function. Especially with stateful fuzzing as it's more likely to generate path dependant interactions.

It can help to compare test outputs to battle-tested implementations; e.g. comparing a custom check that an address is a contract to the OpenZeppelin `Address.isContract` utility.

Stateful fuzzing requires to define invariants, which will basically either be protocol-specific or generic (e.g. `totalSupply`, overflow/underflow in `unchecked` blocks...).

- Note: See Echidna parallel workers, coverage reports; also seems to report invariant violations more friendly than Forge (it tries to report the simplest sequence to reproduce the counterexample and saves it in `reproducers`).

  - it will use events to report the error.

- Obviously some limits to fuzzing, apart from the amount of tests:

  1. How generalized the test cases are, meaning how much did you actually limit the harness, and if you did or not miss out on some edge cases.

  2. How qualitative and exhaustive the invariants you defined are.

## Other methods

There are much more techniques not mentioned here, such as property-based testing, symbolic execution, etc. A great complement to stateful fuzzing is symbolic testing, which will mathematically prove the invariants you defined. For instance, [Halmos](https://github.com/a16z/halmos) that allows to write tests in a way very similar to fuzz tests, except that inputs will be symbolic variables representing all possible values of that type—instead of a random value in this range.

## Additional resources

- [0xNorman, Differential Fuzzing On Solidity Fixed-Point Libraries, 2023-06-28](https://ventral.digital/posts/2023/6/28/differential-fuzzing-on-solidity-fixed-point-libraries).
