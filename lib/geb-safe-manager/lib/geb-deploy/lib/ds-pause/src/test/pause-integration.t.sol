// Copyright (C) 2019 David Terry <me@xwvvvvwx.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.6.7;

import {DSTest} from "ds-test/test.sol";
import {DSProxy} from "ds-proxy/proxy.sol";
import {DSToken} from "ds-token/token.sol";
import {DSDelegateRoles} from "ds-roles/delegate_roles.sol";
import {MultiSigWallet} from "geb-basic-multisig/MultisigWallet.sol";
import {VoteQuorum, VoteQuorumFactory} from "ds-vote-quorum/VoteQuorum.sol";

import "../pause.sol";

// ------------------------------------------------------------------
// Test Harness
// ------------------------------------------------------------------

abstract contract Hevm {
    function warp(uint) virtual public;
}

contract Target {
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address usr) public isAuthorized { authorizedAccounts[usr] = 1; }
    function removeAuthorization(address usr) public isAuthorized { authorizedAccounts[usr] = 0; }
    modifier isAuthorized { require(authorizedAccounts[msg.sender] == 1); _; }

    constructor() public {
        authorizedAccounts[msg.sender] = 1;
    }

    uint public val = 0;
    function set(uint val_) public isAuthorized {
        val = val_;
    }
}

contract Voter {
    function vote(VoteQuorum voteQuorum, address proposal) public {
        address[] memory votes = new address[](1);
        votes[0] = address(proposal);
        voteQuorum.vote(votes);
    }

    function electCandidate(VoteQuorum voteQuorum, address proposal) external {
        voteQuorum.electCandidate(proposal);
    }

    function addVotingWeight(VoteQuorum voteQuorum, uint amount) public {
        DSToken gov = voteQuorum.PROT();
        gov.approve(address(voteQuorum));
        voteQuorum.addVotingWeight(amount);
    }

    function removeVotingWeight(VoteQuorum voteQuorum, uint amount) public {
        DSToken iou = voteQuorum.IOU();
        iou.approve(address(voteQuorum));
        voteQuorum.removeVotingWeight(amount);
    }
}

// ------------------------------------------------------------------
// Gov Proposal Template
// ------------------------------------------------------------------

contract Proposal {
    bool public plotted  = false;

    DSPause public pause;
    address public usr;
    bytes32 public codeHash;
    bytes   public parameters;
    uint    public earliestExecutionTime;

    constructor(DSPause pause_, address usr_, bytes32 codeHash_, bytes memory parameters_, uint earliestExecutionTime_) public {
        pause = pause_;
        codeHash = codeHash_;
        usr = usr_;
        parameters = parameters_;
        earliestExecutionTime = earliestExecutionTime_;
    }

    function scheduleTransaction() external {
        require(!plotted);
        plotted = true;

        earliestExecutionTime = now + pause.delay();
        pause.scheduleTransaction(usr, codeHash, parameters, earliestExecutionTime);
    }

    function executeTransaction() external returns (bytes memory) {
        require(plotted);
        return pause.executeTransaction(usr, codeHash, parameters, earliestExecutionTime);
    }
}

// ------------------------------------------------------------------
// Gov Proposal Template (to abandon a previously created proposal)
// ------------------------------------------------------------------

contract AbandonTransactionProposal {

    DSPause public pause;
    address public usr;
    bytes32 public codeHash;
    bytes   public parameters;
    uint    public earliestExecutionTime;

    constructor(DSPause pause_, address usr_, bytes32 codeHash_, bytes memory parameters_, uint earliestExecutionTime_) public {
        pause = pause_;
        codeHash = codeHash_;
        usr = usr_;
        parameters = parameters_;
        earliestExecutionTime = earliestExecutionTime_;
    }

    function abandonTransaction() external {
        pause.abandonTransaction(usr, codeHash, parameters, earliestExecutionTime);
    }
}


// ------------------------------------------------------------------
// Shared Test Setup
// ------------------------------------------------------------------

contract Test is DSTest {
    // test harness
    Hevm hevm;
    Target target;
    MultiSigWallet multisig;
    VoteQuorumFactory voteQuorumFactory;
    Voter voter;


    // pause timings
    uint delay = 1 days;

    // multisig constants
    address[] owners = [msg.sender];
    uint required = 1;

    // gov constants
    uint votes = 100;
    uint maxBallotSize = 1;

    // gov token
    DSToken gov;

    function setUp() public {
        // init hevm
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);

        // create test harness
        target = new Target();
        voter = new Voter();

        // create gov token
        gov = new DSToken("PROT", "PROT");
        gov.mint(address(voter), votes);
        gov.setOwner(address(0));

        // quorum factory
        voteQuorumFactory = new VoteQuorumFactory();
    }

    function extcodehash(address usr) internal view returns (bytes32 ch) {
        assembly { ch := extcodehash(usr) }
    }
}

// ------------------------------------------------------------------
// Test Simple Voting
// ------------------------------------------------------------------

contract SimpleAction {
    function executeTransaction(Target target, uint value) public {
        target.set(value);
    }
}

contract Integration is Test {

    function test_multisig_dsRecursiveRoles_integration() public {

        DSDelegateRoles roles = new DSDelegateRoles();
        DSPause pause = new DSPause(delay, msg.sender, roles);
        VoteQuorum voteQuorum = voteQuorumFactory.newVoteQuorum(gov, maxBallotSize);

        roles.setAuthority(voteQuorum);

        target.addAuthorization(address(pause.proxy()));
        target.removeAuthorization(address(this));

        assertEq(target.val(), 0);

        owners.push(address(this));

        multisig = new MultiSigWallet(owners, required);
        roles.setOwner(address(multisig));

        assertEq(multisig.owners(0), msg.sender);
        assertEq(multisig.owners(1), address(this));
        assertEq(multisig.required(), 1);
        assertEq(target.val(), 0);

        // proposal
        address      usr = address(new SimpleAction());
        bytes32      codeHash = extcodehash(usr);
        bytes memory proposalParameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 1);
        uint earliestExecutionTime = now + delay;


        // packing proposal for pause
        bytes memory parameters = abi.encodeWithSignature("scheduleTransaction(address,bytes32,bytes,uint256)", usr, codeHash, proposalParameters, earliestExecutionTime);

        // create proposal, automatically executed (only one required approver, see unit tests for tests of quorum)
        multisig.submitTransaction("metadata", address(pause), 0, parameters);

        // execute transaction
        hevm.warp(earliestExecutionTime);
        parameters = abi.encodeWithSignature("executeTransaction(address,bytes32,bytes,uint256)", usr, codeHash, proposalParameters, earliestExecutionTime);

        multisig.submitTransaction("metadata", address(pause), 0, parameters);
        assertEq(target.val(), 1); // effect of proposal execution
    }

    function test_voteQuorum_dsRecursiveRoles_integration() public {

        // DSDelegateRoles
        DSDelegateRoles roles = new DSDelegateRoles();

        // create gov system
        VoteQuorum voteQuorum = voteQuorumFactory.newVoteQuorum(gov, maxBallotSize);
        DSPause pause = new DSPause(delay, msg.sender, roles);

        // adding roles
        roles.setAuthority(voteQuorum);

        target.addAuthorization(address(pause.proxy()));
        target.removeAuthorization(address(this));

        // create proposal
        address      usr = address(new SimpleAction());
        bytes32      codeHash = extcodehash(usr);
        bytes memory parameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 1);

        Proposal proposal = new Proposal(pause, usr, codeHash, parameters, now + delay);

        // make proposal the votedAuthority
        voter.addVotingWeight(voteQuorum, votes);
        voter.vote(voteQuorum, address(proposal));
        voter.electCandidate(voteQuorum, address(proposal));

        // schedule proposal
        proposal.scheduleTransaction();

        // wait until earliestExecutionTime
        hevm.warp(proposal.earliestExecutionTime());

        // execute proposal
        assertEq(target.val(), 0);
        proposal.executeTransaction();
        assertEq(target.val(), 1);
    }

    function test_governance_transition() public {

        // 1. Only multisig rules
        DSDelegateRoles roles = new DSDelegateRoles();
        DSPause pause = new DSPause(delay, msg.sender, roles);

        target.addAuthorization(address(pause.proxy()));
        target.removeAuthorization(address(this));

        assertEq(target.val(), 0);

        owners.push(address(this));

        multisig = new MultiSigWallet(owners, required);
        roles.setOwner(address(multisig));

        assertEq(multisig.owners(0), msg.sender);
        assertEq(multisig.owners(1), address(this));
        assertEq(multisig.required(), 1);
        assertEq(target.val(), 0);

        address      usr = address(new SimpleAction());
        bytes32      codeHash = extcodehash(usr);
        bytes memory proposalParameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 1);
        uint earliestExecutionTime = now + delay;

        bytes memory parameters = abi.encodeWithSignature("scheduleTransaction(address,bytes32,bytes,uint256)", usr, codeHash, proposalParameters, earliestExecutionTime);

        multisig.submitTransaction("First Proposal", address(pause), 0, parameters);

        hevm.warp(earliestExecutionTime);
        parameters = abi.encodeWithSignature("executeTransaction(address,bytes32,bytes,uint256)", usr, codeHash, proposalParameters, earliestExecutionTime);

        multisig.submitTransaction("First Proposal", address(pause), 0, parameters);
        assertEq(target.val(), 1);

        // 2. voteQuorum created
        VoteQuorum voteQuorum = voteQuorumFactory.newVoteQuorum(gov, maxBallotSize);

        // 3. multisig assigns voteQuorum as authority
        usr = address(roles);
        codeHash = extcodehash(usr);
        proposalParameters = abi.encodeWithSignature("setAuthority(address)", address(voteQuorum));
        multisig.submitTransaction("Adding votingQuorum as authority", usr, 0, proposalParameters);

        assertEq(address(roles.authority()), address(voteQuorum));

        // 4. both can transact
        // 4.1 multisig transacts through pause

        usr = address(new SimpleAction());
        codeHash = extcodehash(usr);
        proposalParameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 41);
        earliestExecutionTime = now + delay;

        parameters = abi.encodeWithSignature("scheduleTransaction(address,bytes32,bytes,uint256)", usr, codeHash, proposalParameters, earliestExecutionTime);

        multisig.submitTransaction("First Proposal", address(pause), 0, parameters);

        hevm.warp(earliestExecutionTime);
        parameters = abi.encodeWithSignature("executeTransaction(address,bytes32,bytes,uint256)", usr, codeHash, proposalParameters, earliestExecutionTime);

        multisig.submitTransaction("First Proposal", address(pause), 0, parameters);
        assertEq(target.val(), 41);


        // 4.2 voteQuorum transacts through pause
        usr = address(new SimpleAction());
        codeHash = extcodehash(usr);
        parameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 42);

        Proposal proposal = new Proposal(pause, usr, codeHash, parameters, now + delay);

        voter.addVotingWeight(voteQuorum, votes);
        voter.vote(voteQuorum, address(proposal));
        voter.electCandidate(voteQuorum, address(proposal));

        proposal.scheduleTransaction();

        hevm.warp(proposal.earliestExecutionTime());

        assertEq(target.val(), 41);
        proposal.executeTransaction();
        assertEq(target.val(), 42);

        // 5. multisig sets owner to 0x0
        usr = address(roles);
        codeHash = extcodehash(usr);
        proposalParameters = abi.encodeWithSignature("setOwner(address)", address(0x0));
        multisig.submitTransaction("Revoking governance ownership", usr, 0, proposalParameters);

        assertEq(address(roles.owner()), address(0x0));

        // 5.1 multisig can no longer transact
        usr = address(new SimpleAction());
        codeHash = extcodehash(usr);
        proposalParameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 51);
        earliestExecutionTime = now + delay;

        parameters = abi.encodeWithSignature("scheduleTransaction(address,bytes32,bytes,uint256)", usr, codeHash, proposalParameters, earliestExecutionTime);

        multisig.submitTransaction("First Proposal", address(pause), 0, parameters);

        hevm.warp(earliestExecutionTime);
        parameters = abi.encodeWithSignature("executeTransaction(address,bytes32,bytes,uint256)", usr, codeHash, proposalParameters, earliestExecutionTime);

        multisig.submitTransaction("First Proposal", address(pause), 0, parameters);
        assertEq(target.val(), 42); // no effect

        // 5.2 votingQuorum can still transact
        usr = address(new SimpleAction());
        codeHash = extcodehash(usr);
        parameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 52);

        proposal = new Proposal(pause, usr, codeHash, parameters, now + delay);

        voter.vote(voteQuorum, address(proposal));
        voter.electCandidate(voteQuorum, address(proposal));

        proposal.scheduleTransaction();

        hevm.warp(proposal.earliestExecutionTime());

        assertEq(target.val(), 42);
        proposal.executeTransaction();
        assertEq(target.val(), 52);
    }

    function test_voteQuorum_direct_integration() public {
        // create gov system
        VoteQuorum voteQuorum = voteQuorumFactory.newVoteQuorum(gov, maxBallotSize);
        DSPause pause = new DSPause(delay, address(0x0), voteQuorum);
        target.addAuthorization(address(pause.proxy()));
        target.removeAuthorization(address(this));

        // create proposal
        address      usr = address(new SimpleAction());
        bytes32      codeHash = extcodehash(usr);
        bytes memory parameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 1);

        Proposal proposal = new Proposal(pause, usr, codeHash, parameters, now + delay);

        // make proposal the votedAuthority
        voter.addVotingWeight(voteQuorum, votes);
        voter.vote(voteQuorum, address(proposal));
        voter.electCandidate(voteQuorum, address(proposal));

        // schedule proposal
        proposal.scheduleTransaction();

        // wait until earliestExecutionTime
        hevm.warp(proposal.earliestExecutionTime());

        // execute proposal
        assertEq(target.val(), 0);
        proposal.executeTransaction();
        assertEq(target.val(), 1);
    }
}

// ------------------------------------------------------------------
// Test VoteQuorum Upgrades
// ------------------------------------------------------------------

contract SetAuthority {
    function set(DSAuth usr, DSAuthority authority) public {
        usr.setAuthority(authority);
    }
}

// Temporary DSAuthority that will give a VoteQuorum authority over a pause only
// when a prespecified amount of protocol tokens have been locked in the new vote quorum
contract Guard is DSAuthority {
    // --- data ---
    DSPause public pause;
    VoteQuorum public voteQuorum; // new vote quorum
    uint public limit; // min locked protocol tokens in new vote quorum

    bool public scheduled = false;

    address public usr;
    bytes32 public codeHash;
    bytes   public parameters;
    uint    public earliestExecutionTime;

    // --- init ---

    constructor(DSPause pause_, VoteQuorum voteQuorum_, uint limit_) public {
        pause = pause_;
        voteQuorum = voteQuorum_;
        limit = limit_;

        usr = address(new SetAuthority());
        codeHash = extcodehash(usr);
        parameters = abi.encodeWithSignature("set(address,address)", pause, voteQuorum);
    }

    // --- auth ---

    function canCall(address src, address dst, bytes4 sig) override public view returns (bool) {
        require(src == address(this));
        require(dst == address(pause));
        require(sig == bytes4(keccak256("scheduleTransaction(address,bytes32,bytes,uint256)")));
        return true;
    }

    // --- unlock ---

    function scheduleTransaction() external {
        require(voteQuorum.PROT().balanceOf(address(voteQuorum)) >= limit);
        require(!scheduled);
        scheduled = true;

        earliestExecutionTime = now + pause.delay();
        pause.scheduleTransaction(usr, codeHash, parameters, earliestExecutionTime);
    }

    function executeTransaction() external returns (bytes memory) {
        require(scheduled);
        return pause.executeTransaction(usr, codeHash, parameters, earliestExecutionTime);
    }

    // --- util ---

    function extcodehash(address who) internal view returns (bytes32 soul) {
        assembly { soul := extcodehash(who) }
    }
}


contract UpgradeVoteQuorum is Test {

    function test_quorum_upgrade() public {
        // create gov system
        VoteQuorum oldVoteQuorum = voteQuorumFactory.newVoteQuorum(gov, maxBallotSize);
        DSPause pause = new DSPause(delay, address(0x0), oldVoteQuorum);

        // make pause the only owner of the target
        target.addAuthorization(address(pause.proxy()));
        target.removeAuthorization(address(this));

        // create new quorum
        VoteQuorum newVoteQuorum = voteQuorumFactory.newVoteQuorum(gov, maxBallotSize);

        // create guard
        Guard guard = new Guard(pause, newVoteQuorum, votes);

        // create gov proposal to transfer ownership from the old quorum to the guard
        address      usr = address(new SetAuthority());
        bytes32      codeHash = extcodehash(usr);
        bytes memory parameters = abi.encodeWithSignature("set(address,address)", pause, guard);

        Proposal proposal = new Proposal(pause, usr, codeHash, parameters, now + delay);

        // check that the old quorum is the authority
        assertEq(address(pause.authority()), address(oldVoteQuorum));

        // vote for proposal
        voter.addVotingWeight(oldVoteQuorum, votes);
        voter.vote(oldVoteQuorum, address(proposal));
        voter.electCandidate(oldVoteQuorum, address(proposal));

        // transfer ownership from old quorum to guard
        proposal.scheduleTransaction();
        hevm.warp(proposal.earliestExecutionTime());
        proposal.executeTransaction();

        // check that the guard is the authority
        assertEq(address(pause.authority()), address(guard));

        // move protocol tokens from old quorum to new quorum
        voter.removeVotingWeight(oldVoteQuorum, votes);
        voter.addVotingWeight(newVoteQuorum, votes);

        // plot transaction to transfer ownership from guard to newVoteQuorum
        guard.scheduleTransaction();
        hevm.warp(guard.earliestExecutionTime());
        guard.executeTransaction();

        // check that the new quorum is the authority
        assertEq(address(pause.authority()), address(newVoteQuorum));
    }
}


contract IntegrationVotingScenarios is DSTest {
    // test harness
    Hevm hevm;
    Target target;
    MultiSigWallet multisig;
    VoteQuorumFactory voteQuorumFactory;
    Voter voter1;
    Voter voter2;
    Voter voter3;
    Proposal proposal1;
    Proposal proposal2;
    Proposal proposal3;
    AbandonTransactionProposal abandonProposal1;
    VoteQuorum voteQuorum;

    // pause timings
    uint delay = 1 days;

    // multisig constants
    address[] owners = [msg.sender];
    uint required = 1;

    // gov constants
    uint maxBallotSize = 1;

    // gov token
    DSToken gov;

    function setUp() public {
        // init hevm
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(0);

        // create test harness
        target = new Target();
        voter1 = new Voter();
        voter2 = new Voter();
        voter3 = new Voter();

        // create gov token
        gov = new DSToken("PROT", "PROT");
        gov.mint(address(voter1), 100);
        gov.mint(address(voter2), 1000);
        gov.mint(address(voter3), 1000000000);
        gov.setOwner(address(0));

        // quorum factory
        voteQuorumFactory = new VoteQuorumFactory();

        // create gov system
        voteQuorum = voteQuorumFactory.newVoteQuorum(gov, maxBallotSize);
        DSPause pause = new DSPause(delay, address(0x0), voteQuorum);
        target.addAuthorization(address(pause.proxy()));
        target.removeAuthorization(address(this));

        // create dummy proposals
        address      usr = address(new SimpleAction());
        bytes32      codeHash = extcodehash(usr);
        bytes memory parameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 1);
        proposal1 = new Proposal(pause, usr, codeHash, parameters, now + delay);

        abandonProposal1 = new AbandonTransactionProposal(pause, usr, codeHash, parameters, now + delay);

        usr = address(new SimpleAction());
        parameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 2);
        proposal2 = new Proposal(pause, usr, codeHash, parameters, now + delay);

        usr = address(new SimpleAction());
        parameters = abi.encodeWithSignature("executeTransaction(address,uint256)", target, 3);
        proposal3 = new Proposal(pause, usr, codeHash, parameters, now + delay);
    }

    function extcodehash(address usr) internal view returns (bytes32 ch) {
        assembly { ch := extcodehash(usr) }
    }

    // illustrates the lack of a minimum quorum
    function test_smallVote() public {

        // make proposal 1 the votedAuthority
        voter1.addVotingWeight(voteQuorum, 1);
        voter1.vote(voteQuorum, address(proposal1));
        voter1.electCandidate(voteQuorum, address(proposal1));

        // schedule proposal 1
        proposal1.scheduleTransaction();

        // wait until earliestExecutionTime
        hevm.warp(proposal1.earliestExecutionTime());

        // execute proposal 1
        assertEq(target.val(), 0);
        proposal1.executeTransaction();
        assertEq(target.val(), 1);
    }

    // illustrates how an old proposal can become the voteAuthority
    // just from users unstaking from the contract (removing weight)
    function test_pass_older_proposal() public {

        // make proposal 1 the votedAuthority
        voter1.addVotingWeight(voteQuorum, 100);
        voter1.vote(voteQuorum, address(proposal1));
        voter1.electCandidate(voteQuorum, address(proposal1));

        // make proposal 2 the votedAuthority
        voter2.addVotingWeight(voteQuorum, 200);
        voter2.vote(voteQuorum, address(proposal2));
        voter2.electCandidate(voteQuorum, address(proposal2));

        // schedule proposal 2
        proposal2.scheduleTransaction();
        hevm.warp(proposal2.earliestExecutionTime());

        // execute proposal 2
        assertEq(target.val(), 0);
        proposal2.executeTransaction();
        assertEq(target.val(), 2);

        // make proposal 1 the votedAuthority  once again
        voter2.removeVotingWeight(voteQuorum, 200);
        voter1.electCandidate(voteQuorum, address(proposal1));

        // schedule proposal 1
        proposal1.scheduleTransaction();
        hevm.warp(proposal1.earliestExecutionTime());

        // execute proposal 1
        assertEq(target.val(), 2);
        proposal1.executeTransaction();
        assertEq(target.val(), 1);
    }

    // Illustrates how an atomic transaction and flash loan
    // could be used to make a proposal votedAuthority and then scheduling it
    function test_flash_proposal() public {

        // make proposal 1 the votedAuthority
        voter1.addVotingWeight(voteQuorum, 100);
        voter1.vote(voteQuorum, address(proposal1));
        voter1.electCandidate(voteQuorum, address(proposal1));

        // make proposal 2 the votedAuthority
        /// flashloan, voter2 now has the tokens, all actions from now on to be executed atomically
        voter2.addVotingWeight(voteQuorum, 200);
        voter2.vote(voteQuorum, address(proposal2));
        voter2.electCandidate(voteQuorum, address(proposal2));
        voter2.removeVotingWeight(voteQuorum, 200); // repay the loan

        // schedule proposal 2
        proposal2.scheduleTransaction();
        /// end of atomic tx

        hevm.warp(proposal2.earliestExecutionTime());

        // execute proposal 2
        assertEq(target.val(), 0);
        proposal2.executeTransaction();
        assertEq(target.val(), 2);
    }

    // illustrates how the contract does not check for the majority when setting votedAuthority
    // it just checks against the current votedAuthority
    function test_pass_proposal_without_majority() public {

        // make proposal 1 the votedAuthority
        voter1.addVotingWeight(voteQuorum, 100);
        voter1.vote(voteQuorum, address(proposal1));
        voter1.electCandidate(voteQuorum, address(proposal1));

        // the absolute majority votes on proposal 3, but do not elect it
        voter3.addVotingWeight(voteQuorum, 1000000000);
        voter3.vote(voteQuorum, address(proposal3));

        // voter 2 makes the proposal the votingAuthority, even though it does not have the majority of votes.
        voter2.addVotingWeight(voteQuorum, 200);
        voter2.vote(voteQuorum, address(proposal2));
        voter2.electCandidate(voteQuorum, address(proposal2));

        // schedule proposal 2
        proposal2.scheduleTransaction();
        hevm.warp(proposal2.earliestExecutionTime());

        // execute proposal 2
        assertEq(target.val(), 0);
        proposal2.executeTransaction();
        assertEq(target.val(), 2);
    }

    // test to abandon a transaction that has already been scheduled in Pause
    // Requires governance to vote in a specific proposal to achieve this
    function test_abandonTransaction() public {

        // make proposal 1 the votedAuthority
        voter1.addVotingWeight(voteQuorum, 100);
        voter1.vote(voteQuorum, address(proposal1));
        voter1.electCandidate(voteQuorum, address(proposal1));

        // schedule proposal 1
        proposal1.scheduleTransaction();

        // the community decides to abandon the TX,
        // setting the votedAuthority to a proposal that abandons the previous
        voter2.addVotingWeight(voteQuorum, 200);
        voter2.vote(voteQuorum, address(abandonProposal1));
        voter2.electCandidate(voteQuorum, address(abandonProposal1));

        // execute the proposal that abandons Proposal 1
        abandonProposal1.abandonTransaction();

        // wait until earliestExecutionTime
        hevm.warp(proposal1.earliestExecutionTime());

        // execute proposal 1
        assertEq(target.val(), 0);

        try proposal1.executeTransaction() {
            fail(); // fail test if proposal succeeds
        } catch {}

        assertEq(target.val(), 0); // no effect
    }
}
