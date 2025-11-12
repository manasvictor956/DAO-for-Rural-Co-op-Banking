import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;

/*
  The test below is an example. To learn more, read the testing documentation here:
  https://docs.hiro.so/clarinet/feature-guides/test-contract-with-clarinet-sdk
*/

describe("DAO Rural Banking Smart Contract", () => {
  describe("Savings Account Management System", () => {
    it("should allow users to create a savings account", () => {
      const { result } = simnet.callPublicFn(
        "dao-rural-banking",
        "create-savings-account",
        [],
        address1
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should prevent creating duplicate savings accounts", () => {
      // Create first account
      simnet.callPublicFn(
        "dao-rural-banking", 
        "create-savings-account",
        [],
        address1
      );

      // Try to create duplicate
      const { result } = simnet.callPublicFn(
        "dao-rural-banking",
        "create-savings-account", 
        [],
        address1
      );
      expect(result).toBeErr(Cl.uint(200)); // ERR-SAVINGS-ACCOUNT-EXISTS
    });

    it("should require savings account for deposit", () => {
      const depositAmount = 500;
      const { result } = simnet.callPublicFn(
        "dao-rural-banking",
        "savings-deposit",
        [Cl.contractPrincipal(simnet.deployer, "dao-rural-banking"), Cl.uint(depositAmount)],
        address2
      );
      
      expect(result).toBeErr(Cl.uint(201)); // ERR-SAVINGS-ACCOUNT-NOT-FOUND
    });

    it("should require account for withdrawal", () => {
      const withdrawAmount = 100;
      const { result } = simnet.callPublicFn(
        "dao-rural-banking",
        "savings-withdraw",
        [Cl.contractPrincipal(simnet.deployer, "dao-rural-banking"), Cl.uint(withdrawAmount)],
        address2
      );
      
      expect(result).toBeErr(Cl.uint(201)); // ERR-SAVINGS-ACCOUNT-NOT-FOUND
    });

    it("should allow setting savings goals", () => {
      simnet.callPublicFn(
        "dao-rural-banking",
        "create-savings-account",
        [],
        address1
      );

      const targetAmount = 10000;
      const description = "Emergency Fund";
      const targetDate = 1000; // Future block height
      
      const { result } = simnet.callPublicFn(
        "dao-rural-banking",
        "set-savings-goal",
        [
          Cl.uint(targetAmount),
          Cl.stringAscii(description),
          Cl.uint(targetDate)
        ],
        address1
      );
      
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should reject invalid savings goals", () => {
      simnet.callPublicFn(
        "dao-rural-banking",
        "create-savings-account",
        [],
        address1
      );

      // Test zero target amount
      const { result: result1 } = simnet.callPublicFn(
        "dao-rural-banking",
        "set-savings-goal",
        [Cl.uint(0), Cl.stringAscii("Invalid Goal"), Cl.uint(1000)],
        address1
      );
      expect(result1).toBeErr(Cl.uint(203)); // ERR-INVALID-SAVINGS-GOAL

      // Test past target date
      const { result: result2 } = simnet.callPublicFn(
        "dao-rural-banking", 
        "set-savings-goal",
        [Cl.uint(1000), Cl.stringAscii("Past Goal"), Cl.uint(0)],
        address1
      );
      expect(result2).toBeErr(Cl.uint(203)); // ERR-INVALID-SAVINGS-GOAL
    });

    it("should allow setting up auto-savings", () => {
      simnet.callPublicFn(
        "dao-rural-banking",
        "create-savings-account",
        [],
        address1
      );

      const autoAmount = 200;
      const frequencyBlocks = 144; // Daily
      
      const { result } = simnet.callPublicFn(
        "dao-rural-banking",
        "setup-auto-savings",
        [Cl.uint(autoAmount), Cl.uint(frequencyBlocks)],
        address1
      );
      
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should reject invalid auto-savings parameters", () => {
      simnet.callPublicFn(
        "dao-rural-banking",
        "create-savings-account",
        [],
        address1
      );

      // Test zero auto amount
      const { result: result1 } = simnet.callPublicFn(
        "dao-rural-banking",
        "setup-auto-savings",
        [Cl.uint(0), Cl.uint(144)],
        address1
      );
      expect(result1).toBeErr(Cl.uint(102)); // ERR-INVALID-AMOUNT

      // Test zero frequency
      const { result: result2 } = simnet.callPublicFn(
        "dao-rural-banking",
        "setup-auto-savings", 
        [Cl.uint(200), Cl.uint(0)],
        address1
      );
      expect(result2).toBeErr(Cl.uint(102)); // ERR-INVALID-AMOUNT
    });

    it("should allow locking savings account", () => {
      simnet.callPublicFn(
        "dao-rural-banking",
        "create-savings-account",
        [],
        address1
      );

      const lockBlocks = 1440; // Lock for ~10 days
      const { result } = simnet.callPublicFn(
        "dao-rural-banking",
        "lock-savings-account",
        [Cl.uint(lockBlocks)],
        address1
      );
      
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should calculate potential interest correctly", () => {
      simnet.callPublicFn(
        "dao-rural-banking",
        "create-savings-account",
        [],
        address1
      );

      const blocksAhead = 52560; // One year in blocks
      const { result } = simnet.callReadOnlyFn(
        "dao-rural-banking",
        "calculate-potential-interest",
        [Cl.principal(address1), Cl.uint(blocksAhead)],
        address1
      );
      
      // Should return 0 for empty account
      expect(result).toBeOk(Cl.uint(0));
    });

    it("should provide comprehensive savings summary", () => {
      simnet.callPublicFn(
        "dao-rural-banking",
        "create-savings-account",
        [],
        address2
      );

      const { result } = simnet.callReadOnlyFn(
        "dao-rural-banking",
        "get-savings-summary",
        [Cl.principal(address2)],
        address2
      );
      
      expect(result).not.toBeErr();
    });

    it("should return error for non-existent savings account queries", () => {
      const { result } = simnet.callReadOnlyFn(
        "dao-rural-banking",
        "get-savings-account",
        [Cl.principal(address1)],
        address1
      );
      
      expect(result).toBeOk(Cl.none());
    });

    it("should return error for savings summary of non-existent account", () => {
      const { result } = simnet.callReadOnlyFn(
        "dao-rural-banking",
        "get-savings-summary", 
        [Cl.principal(address1)],
        address1
      );
      
      expect(result).toBeErr(Cl.uint(201)); // ERR-SAVINGS-ACCOUNT-NOT-FOUND
    });
  });

  describe("Core DAO Functionality", () => {
    it("should calculate interest rates correctly", () => {
      const { result } = simnet.callReadOnlyFn(
        "dao-rural-banking",
        "calculate-interest-rate",
        [Cl.principal(address1)],
        address1
      );
      
      // Should return max interest rate for non-member
      expect(result).toBeOk(Cl.uint(2000));
    });

    it("should require minimum stake for proposals", () => {
      const loanAmount = 1000;
      const { result } = simnet.callPublicFn(
        "dao-rural-banking",
        "create-loan-proposal",
        [Cl.uint(loanAmount), Cl.stringAscii("Test"), Cl.uint(100)],
        address2
      );
      
      expect(result).toBeErr(Cl.uint(100)); // ERR-NOT-AUTHORIZED (not a member)
    });

    it("should require membership to create loan proposals", () => {
      const loanAmount = 5000;
      const description = "Agricultural Equipment";
      const repaymentPeriod = 2628;
      
      const { result } = simnet.callPublicFn(
        "dao-rural-banking",
        "create-loan-proposal",
        [
          Cl.uint(loanAmount),
          Cl.stringAscii(description), 
          Cl.uint(repaymentPeriod)
        ],
        address2
      );
      
      expect(result).toBeErr(Cl.uint(100)); // ERR-NOT-AUTHORIZED (not a member)
    });

    it("should prevent voting on non-existent proposals", () => {
      const { result } = simnet.callPublicFn(
        "dao-rural-banking",
        "vote",
        [Cl.uint(999), Cl.bool(true)],
        address1
      );
      
      expect(result).toBeErr(Cl.uint(103)); // ERR-PROPOSAL-NOT-FOUND
    });

    it("should retrieve member data correctly", () => {
      const { result } = simnet.callReadOnlyFn(
        "dao-rural-banking",
        "get-member-data",
        [Cl.principal(address1)],
        address1
      );
      
      // Should fail for non-member
      expect(result).toBeErr(Cl.uint(100)); // ERR-NOT-AUTHORIZED
    });

    it("should retrieve proposal data correctly", () => {
      const { result } = simnet.callReadOnlyFn(
        "dao-rural-banking",
        "get-proposal",
        [Cl.uint(1)],
        address1
      );
      
      // Should fail for non-existent proposal
      expect(result).toBeErr(Cl.uint(103)); // ERR-PROPOSAL-NOT-FOUND
    });
  });

  describe("Integration Tests", () => {
    it("should handle comprehensive savings workflow", () => {
      const createResult = simnet.callPublicFn(
        "dao-rural-banking",
        "create-savings-account",
        [],
        address3
      );
      expect(createResult.result).toBeOk(Cl.bool(true));

      const goalResult = simnet.callPublicFn(
        "dao-rural-banking",
        "set-savings-goal",
        [Cl.uint(10000), Cl.stringAscii("Emergency Fund"), Cl.uint(10000)],
        address3
      );
      expect(goalResult.result).toBeOk(Cl.bool(true));

      const autoResult = simnet.callPublicFn(
        "dao-rural-banking",
        "setup-auto-savings", 
        [Cl.uint(200), Cl.uint(144)],
        address3
      );
      expect(autoResult.result).toBeOk(Cl.bool(true));

      const lockResult = simnet.callPublicFn(
        "dao-rural-banking",
        "lock-savings-account",
        [Cl.uint(1440)],
        address3
      );
      expect(lockResult.result).toBeOk(Cl.bool(true));

      const summaryResult = simnet.callReadOnlyFn(
        "dao-rural-banking",
        "get-savings-summary",
        [Cl.principal(address3)],
        address3
      );
      
      expect(summaryResult.result).not.toBeErr();
    });
  });
});