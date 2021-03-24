pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "../math/SafeMath.sol";

import {SAFEEngine} from 'geb/SAFEEngine.sol';
import {LiquidationEngine} from 'geb/LiquidationEngine.sol';
import {AccountingEngine} from 'geb/AccountingEngine.sol';
import {TaxCollector} from 'geb/TaxCollector.sol';
import 'geb/BasicTokenAdapters.sol';
import {OracleRelayer} from 'geb/OracleRelayer.sol';
import {EnglishCollateralAuctionHouse} from 'geb/CollateralAuctionHouse.sol';
import {GebSafeManager} from "geb-safe-manager/GebSafeManager.sol";

import {SAFESaviourRegistry} from "../SAFESaviourRegistry.sol";
import {cRAIInsurance} from "../saviours/cRaiInsurance.sol";

abstract contract Hevm {
  function warp(uint256) virtual public;
}
contract Feed {
    bytes32 public price;
    bool public validPrice;
    uint public lastUpdateTime;
    address public priceSource;

    constructor(uint256 price_, bool validPrice_) public {
        price = bytes32(price_);
        validPrice = validPrice_;
        lastUpdateTime = now;
    }
    function updatePriceSource(address priceSource_) external {
        priceSource = priceSource_;
    }
    function updateCollateralPrice(uint256 price_) external {
        price = bytes32(price_);
        lastUpdateTime = now;
    }
    function getResultWithValidity() external view returns (bytes32, bool) {
        return (price, validPrice);
    }
}
contract TestSAFEEngine is SAFEEngine {
    uint256 constant RAY = 10 ** 27;

    constructor() public {}

    function mint(address usr, uint wad) public {
        coinBalance[usr] += wad * RAY;
        globalDebt += wad * RAY;
    }
    function balanceOf(address usr) public view returns (uint) {
        return uint(coinBalance[usr] / RAY);
    }
}
contract TestAccountingEngine is AccountingEngine {
    constructor(address safeEngine, address surplusAuctionHouse, address debtAuctionHouse)
        public AccountingEngine(safeEngine, surplusAuctionHouse, debtAuctionHouse) {}

    function totalDeficit() public view returns (uint) {
        return safeEngine.debtBalance(address(this));
    }
    function totalSurplus() public view returns (uint) {
        return safeEngine.coinBalance(address(this));
    }
    function preAuctionDebt() public view returns (uint) {
        return subtract(subtract(totalDeficit(), totalQueuedDebt), totalOnAuctionDebt);
    }
}
contract FakeUser {

    fallback() external payable {}

    function doOpenSafe(
        GebSafeManager manager,
        bytes32 collateralType,
        address usr
    ) public returns (uint256) {
        return manager.openSAFE(collateralType, usr);
    }

    function doSafeAllow(
        GebSafeManager manager,
        uint safe,
        address usr,
        uint ok
    ) public {
        manager.allowSAFE(safe, usr, ok);
    }

    function doHandlerAllow(
        GebSafeManager manager,
        address usr,
        uint ok
    ) public {
        manager.allowHandler(usr, ok);
    }

    function doTransferSAFEOwnership(
        GebSafeManager manager,
        uint safe,
        address dst
    ) public {
        manager.transferSAFEOwnership(safe, dst);
    }

    function doModifySAFECollateralization(
        GebSafeManager manager,
        uint safe,
        int deltaCollateral,
        int deltaDebt
    ) public {
        manager.modifySAFECollateralization(safe, deltaCollateral, deltaDebt);
    }

    function doApproveSAFEModification(
        SAFEEngine safeEngine,
        address usr
    ) public {
        safeEngine.approveSAFEModification(usr);
    }

    function doSAFEEngineModifySAFECollateralization(
        SAFEEngine safeEngine,
        bytes32 collateralType,
        address safe,
        address collateralSource,
        address debtDst,
        int deltaCollateral,
        int deltaDebt
    ) public {
        safeEngine.modifySAFECollateralization(collateralType, safe, collateralSource, debtDst, deltaCollateral, deltaDebt);
    }

    function doProtectSAFE(
        GebSafeManager manager,
        uint safe,
        address liquidationEngine,
        address saviour
    ) public {
        manager.protectSAFE(safe, liquidationEngine, saviour);
    }

    function doDeposit(
        cRAIInsurance saviour,
        uint safe,
        uint amount
    ) public {
        saviour.deposit{value: amount}(safe);
    }

    function doWithdraw(
        cRAIInsurance saviour,
        uint safe,
        uint amount
    ) public {                
        saviour.withdraw(safe, amount);
    }

    function doSetDesiredCollateralizationRatio(
        cRAIInsurance saviour,
        uint safe,
        uint cRatio
    ) public {
        saviour.setDesiredCollateralizationRatio(safe, cRatio);
    }
}

contract CToken is SafeMath{

    uint256 exchangeRate;

    uint256 WAD = 10**18;

    mapping (address => uint) internal accountTokens;


    constructor(uint256 _exchangeRate)public{
        exchangeRate = _exchangeRate;
    }

    function mint() external payable{
        require(msg.value > 0);
        uint256 mintTokens = div(mul(msg.value, WAD), exchangeRate);
        accountTokens[msg.sender] = add(accountTokens[msg.sender], mintTokens);
    }

    function exchangeRateCurrent() external returns (uint256){
        return exchangeRate;
    }

    function redeem(uint cTokenAmount) external returns (uint){

        require(accountTokens[msg.sender] >= cTokenAmount, "cETH/ Not enough balance");

        uint underlyingTokens = mul(exchangeRate, cTokenAmount)/WAD;
        payable(msg.sender).transfer(underlyingTokens);
        accountTokens[msg.sender] = sub(accountTokens[msg.sender], cTokenAmount);
        return 0;
    }

    function redeemUnderlying(uint underlyingTokenAmount) external returns (uint){
        
        require(mul(accountTokens[msg.sender], exchangeRate)/WAD >= underlyingTokenAmount, "cETH/ Not enough balance");
        
        uint256 cTokenAmount = div(mul(underlyingTokenAmount, WAD), exchangeRate);

        payable(msg.sender).transfer(underlyingTokenAmount);
        accountTokens[msg.sender] = sub(accountTokens[msg.sender], cTokenAmount);
        
        return 0;
    }
    
    function isCToken()  external returns (bool){
        return true;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return accountTokens[owner];
    }
}

contract WETH9_ {
    string public name     = "Wrapped Ether";
    string public symbol   = "WETH";
    uint8  public decimals = 18;

    event  Approval(address indexed src, address indexed guy, uint wad);
    event  Transfer(address indexed src, address indexed dst, uint wad);
    event  Deposit(address indexed dst, uint wad);
    event  Withdrawal(address indexed src, uint wad);

    mapping (address => uint)                       public  balanceOf;
    mapping (address => mapping (address => uint))  public  allowance;

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        Deposit(msg.sender, msg.value);
    }
    function withdraw(uint wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        msg.sender.transfer(wad);
        Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint) {
        return address(this).balance;
    }

    function approve(address guy, uint wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        Transfer(src, dst, wad);

        return true;
    }
}

contract cRaiInsuranceTest is DSTest, SafeMath {
    Hevm hevm;

    TestSAFEEngine safeEngine;
    TestAccountingEngine accountingEngine;
    LiquidationEngine liquidationEngine;
    OracleRelayer oracleRelayer;
    TaxCollector taxCollector;

    BasicCollateralJoin collateralA;
    EnglishCollateralAuctionHouse collateralAuctionHouse;

    GebSafeManager safeManager;

    Feed goldFSM;
    Feed goldMedian;

    WETH9_ gold;
    CToken cEth;

    cRAIInsurance saviour;
    SAFESaviourRegistry saviourRegistry;

    FakeUser alice;
    address me;

    // Saviour parameters
    uint256 saveCooldown = 1 days;
    uint256 keeperPayout = 0.5 ether;
    uint256 minKeeperPayoutValue = 0.01 ether;
    uint256 payoutToSAFESize = 40;
    uint256 defaultDesiredCollateralizationRatio = 300;
    uint256 WAD = 10**18;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    fallback() external payable {}

    // Default actions/scenarios
    function default_modify_collateralization(uint256 safe, address safeHandler) internal {
        gold.deposit{value: 100 ether}();
        gold.approve(address(collateralA), 100 ether);
        collateralA.join(address(safeHandler), 100 ether);
        alice.doModifySAFECollateralization(safeManager, safe, 40 ether, 100 ether);
    }
    function default_liquidate_safe(address safeHandler) internal {
        goldMedian.updateCollateralPrice(3 ether);
        goldFSM.updateCollateralPrice(3 ether);
        oracleRelayer.updateCollateralPrice("gold");

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(111 ether));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        // the full SAFE is liquidated
        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", me);
        assertEq(lockedCollateral, 0);
        assertEq(generatedDebt, 0);
        // all debt goes to the accounting engine
        assertEq(accountingEngine.totalQueuedDebt(), rad(100 ether));
        // auction is for all collateral
        (,uint amountToSell,,,,,, uint256 amountToRaise) = collateralAuctionHouse.bids(auction);
        assertEq(amountToSell, 40 ether);
        assertEq(amountToRaise, rad(110 ether));
    }
    function default_repay_all_debt(uint256 safe, address safeHandler) internal {
        alice.doModifySAFECollateralization(safeManager, safe, 0, -100 ether);
    }
    function default_save(uint256 safe, address safeHandler, uint desiredCRatio) internal {
        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        alice.doSetDesiredCollateralizationRatio(saviour, safe, desiredCRatio);
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));

        goldMedian.updateCollateralPrice(3 ether);
        goldFSM.updateCollateralPrice(3 ether);
        oracleRelayer.updateCollateralPrice("gold");

        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());
        alice.doDeposit(saviour, safe, saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());

        assertTrue(saviour.keeperPayoutExceedsMinValue());
        assertTrue(saviour.canSave(safeHandler));

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(111 ether));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        uint256 preSaveKeeperBalance = address(this).balance;
        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        assertEq(auction, 0);
        assertEq(address(this).balance - preSaveKeeperBalance, saviour.keeperPayout());

        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", safeHandler);
        assertEq(lockedCollateral * 3E27 * 100 / (generatedDebt * oracleRelayer.redemptionPrice()), desiredCRatio);
    }
    function default_save(uint256 safe, address safeHandler) internal {
        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));

        goldMedian.updateCollateralPrice(3 ether);
        goldFSM.updateCollateralPrice(3 ether);
        oracleRelayer.updateCollateralPrice("gold");
        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());
        
        alice.doDeposit(saviour, safe, saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());

        assertTrue(saviour.keeperPayoutExceedsMinValue());
        assertTrue(saviour.canSave(safeHandler));

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(111 ether));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        assertEq(auction, 0);

        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", safeHandler);
        assertEq(lockedCollateral * 3E27 * 100 / (generatedDebt * oracleRelayer.redemptionPrice()), saviour.defaultDesiredCollateralizationRatio());
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new TestSAFEEngine();
        safeEngine = safeEngine;


        goldFSM    = new Feed(3.75 ether, true);
        goldMedian = new Feed(3.75 ether, true);
        goldFSM.updatePriceSource(address(goldMedian));

        oracleRelayer = new OracleRelayer(address(safeEngine));
        oracleRelayer.modifyParameters("gold", "orcl", address(goldFSM));
        oracleRelayer.modifyParameters("gold", "safetyCRatio", ray(1.5 ether));
        oracleRelayer.modifyParameters("gold", "liquidationCRatio", ray(1.5 ether));
        safeEngine.addAuthorization(address(oracleRelayer));

        accountingEngine = new TestAccountingEngine(
          address(safeEngine), address(0x1), address(0x2)
        );
        safeEngine.addAuthorization(address(accountingEngine));

        taxCollector = new TaxCollector(address(safeEngine));
        taxCollector.initializeCollateralType("gold");
        taxCollector.modifyParameters("primaryTaxReceiver", address(accountingEngine));
        safeEngine.addAuthorization(address(taxCollector));

        liquidationEngine = new LiquidationEngine(address(safeEngine));
        liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));

        safeEngine.addAuthorization(address(liquidationEngine));
        accountingEngine.addAuthorization(address(liquidationEngine));

        gold = new WETH9_();

        cEth = new CToken(5 * (10 **17));

        safeEngine.initializeCollateralType("gold");
        collateralA = new BasicCollateralJoin(address(safeEngine), "gold", address(gold));
        safeEngine.addAuthorization(address(collateralA));

        safeEngine.modifyParameters("gold", "safetyPrice", ray(1 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(1000 ether));
        safeEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

        collateralAuctionHouse = new EnglishCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), "gold");
        collateralAuctionHouse.addAuthorization(address(liquidationEngine));

        liquidationEngine.addAuthorization(address(collateralAuctionHouse));
        liquidationEngine.modifyParameters("gold", "collateralAuctionHouse", address(collateralAuctionHouse));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1 ether);

        safeEngine.addAuthorization(address(collateralAuctionHouse));
        safeEngine.approveSAFEModification(address(collateralAuctionHouse));

        safeManager = new GebSafeManager(address(safeEngine));
        oracleRelayer.updateCollateralPrice("gold");

        saviourRegistry = new SAFESaviourRegistry(saveCooldown);
        saviour = new cRAIInsurance(
            address(collateralA),
            address(liquidationEngine),
            address(oracleRelayer),
            address(safeEngine),
            address(safeManager),
            address(saviourRegistry),
            keeperPayout,
            minKeeperPayoutValue,
            payoutToSAFESize,
            defaultDesiredCollateralizationRatio,
            address(cEth)
        );
        saviourRegistry.toggleSaviour(address(saviour));
        liquidationEngine.connectSAFESaviour(address(saviour));

        me    = address(this);
        alice = new FakeUser();

        payable(address(alice)).transfer(500 ether);

    }

    function test_deposit_as_owner() public {
        assertEq(liquidationEngine.safeSaviours(address(saviour)), 1);

        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        payable(address(alice)).transfer(200 ether);
        alice.doDeposit(saviour, safe, 200 ether);

        assertEq(cEth.balanceOf(address(saviour)), div(mul(200 ether, WAD), cEth.exchangeRateCurrent()));
        assertEq(saviour.collateralCover(safeHandler), div(mul(200 ether, WAD), cEth.exchangeRateCurrent()));
    }
    function test_deposit_as_random() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        gold.approve(address(saviour), 500 ether);
        saviour.deposit{value: 500 ether}(safe);

        assertEq(cEth.balanceOf(address(saviour)), div(mul(500 ether, WAD), cEth.exchangeRateCurrent()));
        assertEq(saviour.collateralCover(safeHandler), div(mul(500 ether, WAD), cEth.exchangeRateCurrent()));
    }
    function testFail_deposit_after_repaying_debt() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        saviour.deposit{value: 250 ether}(safe);

        default_repay_all_debt(safe, safeHandler);
        saviour.deposit{value: 250 ether}(safe);
    }
    function testFail_deposit_when_no_debt() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        saviour.deposit{value: 500 ether}(safe);
    }
    function testFail_deposit_when_not_engine_approved() public {
        liquidationEngine.disconnectSAFESaviour(address(saviour));

        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        saviour.deposit{value: 250 ether}(safe);
    }
    function test_deposit_then_withdraw_as_owner() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        payable(address(alice)).transfer(500 ether);
        alice.doDeposit(saviour, safe, 500 ether);

        alice.doWithdraw(saviour, safe, div(mul(100 ether, WAD), cEth.exchangeRateCurrent()));
        assertEq(cEth.balanceOf(address(saviour)), div(mul(400 ether, WAD), cEth.exchangeRateCurrent()));
        assertEq(saviour.collateralCover(safeHandler), div(mul(400 ether, WAD), cEth.exchangeRateCurrent()));

        alice.doWithdraw(saviour, safe, div(mul(400 ether, WAD), cEth.exchangeRateCurrent()));
        assertEq(cEth.balanceOf(address(saviour)), 0);
        assertEq(saviour.collateralCover(safeHandler), 0);
    }
    function test_withdraw_when_safe_has_no_debt() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        payable(address(alice)).transfer(500 ether);
        alice.doDeposit(saviour, safe, 500 ether);

        default_repay_all_debt(safe, safeHandler);
        alice.doWithdraw(saviour, safe, div(mul(500 ether, WAD), cEth.exchangeRateCurrent()));
        assertEq(cEth.balanceOf(address(saviour)), 0);
        assertEq(saviour.collateralCover(safeHandler), 0);
    }
    function test_deposit_then_withdraw_as_approved() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);
        uint256 preBalance = address(this).balance;
        payable(address(alice)).transfer(500 ether);
        alice.doDeposit(saviour, safe, 500 ether);

        assertEq(address(this).balance, sub(preBalance, 500 ether));

        alice.doSafeAllow(safeManager, safe, address(this), 1);
        saviour.withdraw(safe, div(mul(250 ether, WAD),cEth.exchangeRateCurrent()));

        assertEq(address(this).balance, sub(preBalance, 250 ether));
        assertEq(cEth.balanceOf(address(saviour)), div(mul(250 ether, WAD),cEth.exchangeRateCurrent()));
        assertEq(saviour.collateralCover(safeHandler), div(mul(250 ether, WAD),cEth.exchangeRateCurrent()));
    }
    function testFail_deposit_then_withdraw_as_non_approved() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);
        uint256 preBalance = address(this).balance;

        payable(address(alice)).transfer(500 ether);
        alice.doDeposit(saviour, safe, 500 ether);

        assertEq(address(this).balance, sub(preBalance, 500 ether));
        saviour.withdraw(safe, div(mul(250 ether, WAD), cEth.exchangeRateCurrent()));
    }
    function test_set_desired_cratio_by_owner() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        alice.doSetDesiredCollateralizationRatio(saviour, safe, 151);
        assertEq(saviour.desiredCollateralizationRatios("gold", safeHandler), 151);
    }
    function test_set_desired_cratio_by_approved() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        alice.doSafeAllow(safeManager, safe, address(this), 1);
        saviour.setDesiredCollateralizationRatio(safe, 151);
        assertEq(saviour.desiredCollateralizationRatios("gold", safeHandler), 151);
    }
    function testFail_set_desired_cratio_by_unauthed() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        saviour.setDesiredCollateralizationRatio(safe, 151);
    }
    function testFail_set_desired_cratio_above_max_limit() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        alice.doSafeAllow(safeManager, safe, address(this), 1);
        saviour.setDesiredCollateralizationRatio(safe, saviour.MAX_CRATIO() + 1);
    }
    function test_liquidate_no_saviour_set() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);
        default_liquidate_safe(safeHandler);
    }
    function test_add_remove_saviour_from_manager() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));
        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(0));
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(0));
    }
    function test_liquidate_add_saviour_with_no_cover() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        alice.doSetDesiredCollateralizationRatio(saviour, safe, 200);

        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));
        assertTrue(!saviour.canSave(safeHandler));
        assertTrue(saviour.keeperPayoutExceedsMinValue());
        assertEq(saviour.tokenAmountUsedToSave(safeHandler), 13333333333333333333);

        default_liquidate_safe(safeHandler);
    }
    function test_liquidate_cover_only_for_keeper_payout() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        alice.doSetDesiredCollateralizationRatio(saviour, safe, 200);

        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));
        assertTrue(saviour.keeperPayoutExceedsMinValue());
        assertEq(saviour.getKeeperPayoutValue(), 1.875 ether);

        payable(address(alice)).transfer(saviour.keeperPayout());
        alice.doDeposit(saviour, safe, saviour.keeperPayout());

        assertTrue(!saviour.canSave(safeHandler));
        default_liquidate_safe(safeHandler);
    }
    function test_liquidate_cover_only_no_keeper_payout() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        alice.doSetDesiredCollateralizationRatio(saviour, safe, 200);
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));

        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler));
        alice.doDeposit(saviour, safe, saviour.tokenAmountUsedToSave(safeHandler));

        assertTrue(!saviour.canSave(safeHandler));
        default_liquidate_safe(safeHandler);
    }
    function test_liquidate_keeper_payout_value_small() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        alice.doSetDesiredCollateralizationRatio(saviour, safe, 200);
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));

        goldMedian.updateCollateralPrice(0.02 ether - 1);
        goldFSM.updateCollateralPrice(0.02 ether - 1);

        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));
        assertEq(saviour.getKeeperPayoutValue(), 9999999999999999);

        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());
        alice.doDeposit(saviour, safe, saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());

        assertTrue(!saviour.keeperPayoutExceedsMinValue());
        assertTrue(saviour.canSave(safeHandler));

        // Liquidate with the current 0.02 ether - 1 price
        oracleRelayer.updateCollateralPrice("gold");

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(111 ether));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        // the full SAFE is liquidated
        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", me);
        assertEq(lockedCollateral, 0);
        assertEq(generatedDebt, 0);
        // all debt goes to the accounting engine
        assertEq(accountingEngine.totalQueuedDebt(), rad(100 ether));
        // auction is for all collateral
        (,uint amountToSell,,,,,, uint256 amountToRaise) = collateralAuctionHouse.bids(auction);
        assertEq(amountToSell, 40 ether);
        assertEq(amountToRaise, rad(110 ether));
    }
    function test_successfully_save_small_cratio() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_save(safe, safeHandler, 200);
    }
    function test_successfully_save_max_cratio() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_save(safe, safeHandler, saviour.MAX_CRATIO());
    }
    function test_successfully_save_default_cratio() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_save(safe, safeHandler);
    }
    function test_liquidate_twice_in_row_same_saviour() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_save(safe, safeHandler, 155);

        // Add collateral and try to save again
        goldMedian.updateCollateralPrice(2 ether);
        goldFSM.updateCollateralPrice(2 ether);
        oracleRelayer.updateCollateralPrice("gold");

        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());
        alice.doDeposit(saviour, safe, saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());

        assertTrue(saviour.keeperPayoutExceedsMinValue());
        assertTrue(saviour.canSave(safeHandler));

        // Can't save because the SAFE saviour registry break time hasn't elapsed
        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        assertEq(auction, 1);
    }
    function test_liquidate_twice_in_row_different_saviours() public {
        // Create a new saviour and set it up
        cRAIInsurance secondSaviour = new cRAIInsurance(
            address(collateralA),
            address(liquidationEngine),
            address(oracleRelayer),
            address(safeEngine),
            address(safeManager),
            address(saviourRegistry),
            keeperPayout,
            minKeeperPayoutValue,
            payoutToSAFESize,
            defaultDesiredCollateralizationRatio,
            address(cEth)
        );
        saviourRegistry.toggleSaviour(address(secondSaviour));
        liquidationEngine.connectSAFESaviour(address(secondSaviour));

        // Save the safe with the original saviour first
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_save(safe, safeHandler, 155);

        // Try to save with the second saviour afterwards
        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(secondSaviour));
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(secondSaviour));

        goldMedian.updateCollateralPrice(1.5 ether);
        goldFSM.updateCollateralPrice(1.5 ether);
        oracleRelayer.updateCollateralPrice("gold");

        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());
        alice.doDeposit(secondSaviour, safe, secondSaviour.tokenAmountUsedToSave(safeHandler) + secondSaviour.keeperPayout());

        assertTrue(secondSaviour.keeperPayoutExceedsMinValue());
        assertTrue(secondSaviour.canSave(safeHandler));

        // Can't save because the SAFE saviour registry break time hasn't elapsed
        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        assertEq(auction, 1);
    }
}
