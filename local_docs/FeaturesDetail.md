## Campaign State

If the creator choose to withdraw funds only after the campaign reaches its funding goal,
the Campaign would fail if it does not reach its funding goal by the deadline set during creation. Then the funds would be returned to the donors.

## Token Reception

If the creator choose to withdraw funds only after the campaign reaches its funding goal, then the donor would not receive their tokens until that point. This means donor would not receive any tokens if the campaign fails to meet its goal.

## Creator's Token

The creator can set a **Creator Reserve Percentage** when launching the campaign.

- **Automatic Minting**  
  A fixed portion of the total token supply (e.g., 10–20%) is automatically minted and allocated to the creator’s wallet.  
  This ensures that the creator always holds tokens required for liquidity bootstrapping or future incentive alignment.

- **Liquidity Provision Option**  
  If the creator selects the _Token Launch_ resolution, part of the raised funds (ETH/USDC) will be paired with the creator’s reserved tokens to automatically create a liquidity pool on a DEX.

  - Example: 15% of raised funds + creator’s reserved tokens are locked into Uniswap liquidity.
  - The liquidity pool can optionally be locked via a third-party service to build backer trust.

- **Transparency**  
  The Creator Reserve Percentage and Liquidity Allocation are declared at campaign creation and recorded on-chain.  
  Backers know upfront how many tokens will be distributed to donors vs. reserved for the creator, ensuring fairness and preventing hidden minting.

- **Alignment of Incentives**  
  By holding a portion of the campaign tokens, the creator’s long-term interests are tied to the success of the project and the value of the token, reducing risks of “raise and abandon.”
