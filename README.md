# cRaiEthInsurance

# Challenge

https://gitcoin.co/issue/reflexer-labs/geb/99/100024983
To build an insurance solution where Safe owners can deposit ETH on [Compound](https://compound.finance/docs/ctokens) and keep the received cETH in a saviour contract. When a Safe gets liquidated, the saviour should redeem ETH from Compound and add it in the Safe.


# Solution

Created a deposit function to receive Eth and mint cEth on compound, and update collateral cover in terms of cEth. In other implementations it makes sense to keep collateral cover in terms of underlying collateral, but here after depositing ETH to compound, it will keep increasing in amount, and it made sense to keep track of it in terms of cEth.

While withdrawing or saving safe, we can calculate underlying Eth for cEth by multiplying current exchange rate of cEth with amount of cEth.

Created a withdrawal function which redeem cEth tokens in exchange of Eth and transfer it back to caller of the function, hence owner of safe should be careful in giving access to his safe, because it will also give him access to withdraw collateral kept in cRaiEthInsurance

When liquidation occurs, liquidation engine calls saveSafe function of saviour method, which calculates amount of collateral required to save safe and then, call redeemUnderlying function of cEth to get required collateral which is Eth back, and then convert it into WETH and approve amount required for collateral join, and then we mark it save in SaviourRegistry and modifySafeCollateralization of safeEngine and repay keeper the reward amount


# Kovan Testing
Contract Address for Kovan: https://kovan.etherscan.io/address/0xae1623b164c5c3bf59c3c5316f2c9951c8d0b62c

Min Keeper Payout: 50 USD

Keeper Payout: 0.1 eth

In liquidation call 0.000457505 ether was total spent on gas, given 1 Gwei as gas cost, if we scale it to 200 Gwei gas cost on mainnet, it comes to be about 0.08 eth, giving 0.02 eth as profit for keeper. We can increase this value more to a more acceptable number, but keeping it atleast 0.1 eth looks like good idea to ensure proper incentive for keeper

payoutToSAFESize: 20 (was kept 20 for testing purpose, can be increased to 50 or 100, and should be adjustable for each safe)

Created a safe with id: 214

Collateral : 3 Eth

Debt : 1181 RAI

[Attached saviour for safe](https://kovan.etherscan.io/tx/0x6b12d0af25a3ee0a32ea4bf4a2e635b60e7bd9a012c1fadd73a1750cd3123110)

[Deposited 1.5 eth in insurance contract](https://kovan.etherscan.io/tx/0xda9a75bef7c5ce7bed7d70cd614a2f9b2240d6cc0348b9c69ee393ebe91423ca)
cEth minted : 65.35597348

On collateral price below 145%, I triggered liquidateSafe method of Liquidation Engine
https://kovan.etherscan.io/tx/0x4f97ff9afac1de1029296611fc6ed6e68f18fdbe28f8fefd8c04bdd9474da006
cRaiEthInsurance contract redeemed 55.06044069 cEth for 1.263781231907857744 eth, and transferred 0.1 eth to keeper and left to change collateral ration to 200
