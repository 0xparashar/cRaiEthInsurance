<h1 align="center">
ds-pause
</h1>

<p align="center">
<i><code>delegatecall</code> based proxy with an enforced delay</i>
</p>

`ds-pause` allows authorized users to schedule function calls that can only be executed once some
predetermined waiting period has elapsed. The configurable `delay` attribute sets the minimum wait
time.

`ds-pause` is designed to be used as a component in a governance system, to give affected parties
time to respond to decisions. If those affected by governance decisions have e.g. exit or veto
rights, then the pause can serve as an effective check on governance power.

Check out the more comprehensive [documentation](https://docs.reflexer.finance/system-contracts/governance-module/ds-pause).

## Invariants

A break of any of the following would be classified as a critical issue. Please submit bug reports
to security@reflexer.finance.

**high level**
- There is no way to bypass the delay
- The code executed by the `delegatecall` cannot directly modify storage on the pause
- The pause will always retain ownership of it's `proxy`

**admin**
- `authority`, `owner`, and `delay` can only be changed if an authorized user creates a `scheduledTransaction` to do so

**`scheduledTransactions`**
- A `scheduledTransaction` can only be plotted if its `earliestExecutionTime` is after `block.timestamp + delay`
- A `scheduledTransaction` can only be plotted by authorized users

**`attachTransactionDescription`**
- A `attachTransactionDescription` can only be called by the authority

**`protestAgainstTransaction`**
- A `protestAgainstTransaction` can only be called once per scheduled transaction
- A `protestAgainstTransaction` cannot delay an unscheduled transaction
- A `protestAgainstTransaction` cannot delay a transaction more than `delay * MAX_MULTIPLIER` (unless it's not already delayed more than that)

**`executeTransaction`**
- A `scheduledTransaction` can only be executed if it has previously been plotted
- A `scheduledTransaction` can only be executed once it's `earliestExecutionTime` has passed
- A `scheduledTransaction` can only be executed if its `codeHash` matches `extcodehash(usr)`
- A `scheduledTransaction` can only be executed once
- A `scheduledTransaction` can be executed by anyone

**`abandonTransaction`**
- A `scheduledTransaction` can only be dropped by authorized users

## Example Usage

```solidity
// construct the pause

uint delay            = 2 days;
address owner         = address(0);
DSAuthority authority = new DSAuthority();

DSPause pause = new DSPause(delay, owner, authority); OR DSProtestPause pause = new DSProtestPause(delay, owner, authority);

// schedule the transaction

address      usr = address(0x0);
bytes32      codeHash;  assembly { codeHash := extcodehash(usr) }
bytes memory parameters = abi.encodeWithSignature("sig()");
uint         earliestExecutionTime = now + delay;

pause.scheduleTransaction(usr, codeHash, parameters, earliestExecutionTime);
```

```solidity
// wait until block.timestamp is at least now + delay...
// and then execute the scheduledTransaction

bytes memory out = pause.executeTransaction(usr, codeHash, parameters, earliestExecutionTime);
```

## Tests

- [`pause.t.sol`](./pause.t.sol): unit tests for vanilla DSPause
- [`protest-pause.t.sol`](./protest-pause.t.sol): unit tests for DSProtestPause
- [`integration.t.sol`](./integration.t.sol): usage examples / integation tests for vanilla DSPause
- [`protest-pause-integration.t.sol`](./protest-pause.t.sol): usage examples / integation tests for DSProtestPause
