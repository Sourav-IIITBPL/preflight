// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {TokenGuardResult} from "../../src/guards/interfaces/ITokenGuard.sol";
import {TokenGuardHarness, CleanTokenSample, FeatureRichTokenSample, RenouncedOwnerTokenSample, CloneImplementationSample, CloneFactorySample} from "../mocks/TokenGuardHarnesses.sol";

contract TokenGuardLibraryTest is Test {
    TokenGuardHarness internal harness;

    function setUp() public {
        harness = new TokenGuardHarness();
    }

    function test_nonContractFlagsNotAContractAndEmptyBytecode() public {
        TokenGuardResult memory result = harness.check(address(0x1234));
        assertTrue(result.NOT_A_CONTRACT);
        assertTrue(result.EMPTY_BYTECODE);
    }

    function test_featureRichTokenSetsAdministrativeAndHeuristicFlags() public {
        FeatureRichTokenSample token = new FeatureRichTokenSample();
        TokenGuardResult memory result = harness.check(address(token));

        assertTrue(result.WEIRD_DECIMALS);
        assertTrue(result.HIGH_DECIMALS);
        assertTrue(result.VERY_LOW_TOTAL_SUPPLY);
        assertTrue(result.HAS_OWNER);
        assertTrue(result.OWNER_IS_EOA);
        assertTrue(result.IS_PAUSABLE);
        assertTrue(result.IS_CURRENTLY_PAUSED);
        assertTrue(result.HAS_BLACKLIST);
        assertTrue(result.HAS_BLOCKLIST);
        assertTrue(result.POSSIBLE_FEE_ON_TRANSFER);
        assertTrue(result.HAS_TRANSFER_FEE_GETTER);
        assertTrue(result.HAS_TAX_FUNCTION);
        assertTrue(result.POSSIBLE_REBASING);
        assertTrue(result.HAS_MINT_CAPABILITY);
        assertTrue(result.HAS_BURN_CAPABILITY);
        assertTrue(result.HAS_PERMIT);
        assertTrue(result.HAS_FLASH_MINT);
        assertTrue(result.IS_EIP1967_PROXY);
        assertTrue(result.IS_EIP1822_PROXY);
    }

    function test_renouncedOwnershipIsDetected() public {
        RenouncedOwnerTokenSample token = new RenouncedOwnerTokenSample();
        TokenGuardResult memory result = harness.check(address(token));

        assertTrue(result.OWNERSHIP_RENOUNCED);
        assertFalse(result.HAS_OWNER);
    }

    function test_cleanTokenRemainsMostlyClear() public {
        CleanTokenSample token = new CleanTokenSample();
        TokenGuardResult memory result = harness.check(address(token));

        assertFalse(result.NOT_A_CONTRACT);
        assertFalse(result.WEIRD_DECIMALS);
        assertFalse(result.ZERO_TOTAL_SUPPLY);
        assertFalse(result.HAS_OWNER);
        assertFalse(result.HAS_PERMIT);
        assertFalse(result.HAS_FLASH_MINT);
    }

    function test_minimalProxyDetectionWorks() public {
        CloneImplementationSample implementation = new CloneImplementationSample();
        CloneFactorySample factory = new CloneFactorySample();
        address clone = factory.clone(address(implementation));

        TokenGuardResult memory result = harness.check(clone);
        assertTrue(result.IS_MINIMAL_PROXY);
    }
}
