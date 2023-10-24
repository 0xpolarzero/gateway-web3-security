- Need a Keeper to check the price of the underlying asset and trigger liquidations if necessary.
- Need price feeds for the underlying asset and the collateral.

- Aggregate the open interest (both long and short) in USD
  -> incremented each time a position is opened or increased
  --> allows to convert to open interest in token units
  ---> allows to keep track of the protocol solvency depending on the price of the underlying asset

-> whenever someone deposits/withdraws, we can know the net value of the protocol
--> Allows to track in real-time to avoid stepwise jumps (which are easily vulnerable to front-running)
---> So whenever there is a deposit/withdraw, it does take the current LP value (which itself depends on the current total PnL) into account, thus avoiding stepwise jumps that would occur if we were to update this LP value periodically (e.g. only when a position is opened/closed).

- On a short, the PnL can't go higher than the borrowed amount (since the price can't go below 0) (borrowed amount - current price)
- On a long, the PnL is unlimited, so it needs to be limited: see the formula in the docs

See ERC4626 Vault to account for people's deposits (liquidity providers) simply (of course modified) and share fees based on the amount of liquidity provided.

LP Value = Total deposits - Total PnL
-> Calculate shares of providers (ERC4626) based on LP Value
-> Override `totalAssets` to actually return the LPValue
-> Override \_withdraw to perform checks that the invariants are not broken (meaning it can handle the current PnL eventual redeems)
