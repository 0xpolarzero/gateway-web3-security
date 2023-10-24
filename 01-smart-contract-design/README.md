# Principles of Smart Contract Design

_These are a mix of principles described by Owen and my own additional observations._

### 1. Keep the code as short as possible

**Guidelines**

- Related to [DRY (Don't Repeat Yourself)](https://www.plutora.com/blog/understanding-the-dry-dont-repeat-yourself-principle).

  - which incidentally makes code easier to maintain and issues less error-prone to fix.

- Avoids introducing unnecessary complexity, gas cost, and potential vulnerabilities that come with duplicate variables/parameters (e.g. superfluous storage variable) or code.

- Also reduces the audit cost (when charged by sLOC).

**Strategies**

- Be extremely picky about storage variables.

- Unload the smart contract from expensive computation that can be done off-chain (e.g. using [Chainlink Functions](https://chain.link/functions) or [Automation](https://chain.link/automation) to still perform it securely).

- It helps to think about good _design_ rather than good _code_—which will eventually be a consequence of good design.

### 2. Avoid loops whenever possible

**Guidelines**

- `for`/`while` loops (or any loop that uses indeterminate amount of gas) are not reliable and should be avoided.

  - mostly DoS due to unbounded and unexpected gas consumption;
  - especially if there are some external calls inside the loop;
  - gas-wise, be careful of events and storage writes inside loops, as they can often rather be done/emitted _after_ the loop.

- Often, they _seem_ necessary when they can actually be replaced for a more efficient and reliable solution.

      - e.g. tracking a "total" value from the start instead of aggregating it from separate values in a loop; or sometimes, it can even just be derived from another value that already exists.

**Strategies**

- When reading values in a loop, consider if there is a way to derive the value from anything else that already exists.

- Always consider the gas cost, and the possibility of a loop that can't be completed—at some point, it can even become so expensive that it won't even be able to complete anymore.

- Consider off-chain computation solutions.

- Use existing standards for iterative processes (e.g. ERC721A for multiple token mints)

- Emit events outside of loops if possible (e.g. `OperationABatch` instead of repeating `OperationA`).

### 3. Be explicit about expected inputs

**Guidelines**

- Be explicit about behaviors that might not make sense, yet are still possible. It might make sense to cut off some paths that are not expected, even if they are not necessarily harmful.

      - e.g. if a user can create a position in a DeFi protocol with 0 size and 0 collateral; this doesn't really make sense, yet it might be better to explicitly disallow it;

  - generally it's good to think that something unexpected _in_ might produce something unexpected _out_;
  - a zero address check is a good example, but it is really just the tip of the iceberg, as it also concerns protocol-specific checks.

- Example of GMX where they had to implement a minimum size for the positions to completely eliminate the risk for manipulation. Meaning not just restricting 0 size, but also any size that is too small to be be correctly handled.

**Strategies**

- **As a developer**, cut off any path that is not expected, right at the input, even if it doesn't seem necessarily harmful.
- **As an auditor**, figure out any input that might not be expected, and see if it can indeed produce an unexpected output.

### 4. Handle all cases

**Guidelines**

- It might seem related to **3**, but it's about considering what can't be simply reverted/handled at the input—meaning taking care of _all_ possibilities.

      - e.g. even though you made sure a stablecoin _cannot_ depeg, handle the case where it _does_ depeg.
      - e.g. a user should _never_ reach a certain collateralization ratio, because they should be liquidated _long_ before; but what if the keepers in charge of doing so actually fail to do so? what if the network gets too congested during rapid price movements? what if then, the calculation cannot be handled correctly anymore (underflow/overflow)?

**Strategies**

- **As a developer**:

  - be careful about the cases that you believe _cannot_ happen, when they actually _should'nt_ happen yet have a chance, even the slightest, to occur;
  - these should be at least described and thoroughly considered during the audit, to figure out if they need to be handled or not.

- **As an auditor**:
  - pay extra attention to the developer's assumptions, this is often where the most critical issues are found;
  - comments can partially help understand the developer's assumptions;
  - be careful about your _own_ assumptions as well, as they might completely prevent you from confronting an assumed invariant.

### 5. Parallel data structures updates

**Guidelines**

- A specific case about the benefits of having less code by being smart about storage variables layout.

- Basically when having two pieces of state that track more or less the same thing, the updates need to be performed with special care (especially when deleting).

  - To explain it practically:

  ```solidity
  struct Position {
    // ...
    uint256 index; // index in the array
  }

  mapping(address => Position) positionsMapping;
  Position[] positionsArray

  function removePosition(address _user) {
    Position memory position = positionsMapping[_user];
    delete positionsMapping[_user];

    if (positionsArray.length > 1) {
      uint256 index = position.index;

      // Replace the position to remove with the last position in the array
      positionsArray[index] = positionsArray[positionsArray.length - 1];
      // Remove the last position in the array
      positionsArray.pop();

      // The demonstrated example that is vulnerable stops here
      // It's critical to also update the index of the swapped position
      positionsArray[index].index = index;
    }
  }
  ```

**Strategies**

- Generally, parallel data structures updates are considered a bad practice, and should be avoided unless absolutely necessary.

- In the case where a mapping needs to be iterated like an array, it's possible to use OpenZeppelin [EnumerableMap](https://docs.openzeppelin.com/contracts/4.x/api/utils#EnumerableMap) or [EnumerableSet](https://docs.openzeppelin.com/contracts/4.x/api/utils#EnumerableSet) to keep track of the keys.
