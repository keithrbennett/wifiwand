# macOS Redacted Network Names Policy

_Last updated: 2026-04-25_

This document explains the problem created by macOS WiFi-name redaction, the
behavioral conflicts it introduces in `wifi-wand`, and the implementation
decision for commands and test-state restoration.

It is an internal design note for maintainers. It is not end-user setup
documentation. User-facing remediation belongs in [docs/MACOS_SETUP.md](/home/kbennett/code/wifiwand/primary/docs/MACOS_SETUP.md)
and related operator docs.

## Purpose

The project needs a consistent policy for commands whose contract depends on
knowing the current SSID exactly.

On modern macOS, Location Services permission is sometimes required before the
OS will reveal WiFi network names. Without that permission:

- the radio may still be associated with a network
- `wifi-wand` may still be able to detect generic association
- but the OS may hide the actual SSID as `<hidden>`, `<redacted>`, blank, or
  `nil`

That creates a gap between:

- "the interface is associated with some network"
- and "the interface is confirmed to be associated with the requested/original
  SSID"

This note defines how `wifi-wand` should behave when that gap exists.

## Background

### Relevant Current Behavior

The following parts of the codebase matter here:

- [lib/wifi-wand/models/mac_os_model.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/models/mac_os_model.rb)
- [lib/wifi-wand/services/connection_manager.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/connection_manager.rb)
- [lib/wifi-wand/services/network_state_manager.rb](/home/kbennett/code/wifiwand/primary/lib/wifi-wand/services/network_state_manager.rb)

Important distinctions:

- `associated?` can be true on macOS even when the exact SSID is not available.
- `connected_network_name` can be `nil` because placeholder SSIDs are filtered
  out.
- `connection_ready?(network_name)` requires exact SSID identity.
- restore logic for disruptive tests is stricter than generic association: it is
  intended to return the machine to the original network, not merely to "some
  network."

### Why This Happens

Apple treats WiFi SSIDs as location-sensitive information. On affected macOS
versions, the OS may allow an app to determine that WiFi is active and that the
interface is associated, while still withholding the actual SSID unless
Location Services has been granted to the helper or calling process.

From `wifi-wand`'s perspective, this means:

- the OS may expose enough signal to say "association exists"
- but not enough signal to say "association is to SSID X"

## Problem Statement

Commands and workflows fall into two groups:

1. Operations that only need radio state or generic association
2. Operations whose contract depends on confirming an exact SSID

The second group becomes ambiguous when macOS redacts network names.

Examples:

- `connect SomeSSID`
- restore of a previously captured test network state
- any API or command that must answer "am I on SSID X?"

If `wifi-wand` silently treats generic association as equivalent to exact SSID
verification, it can produce false positives.

If `wifi-wand` always raises a hard failure whenever SSID verification is
impossible, it can make some commands unusable for users who knowingly operate
without Location Services permission.

This is not merely a UI concern. It is a contract and policy concern.

## Concrete Failure Modes

### 1. False Success On The Wrong Network

This is the restore-path bug already identified in `NetworkStateManager`.

After a disconnect, macOS may auto-reassociate to a remembered preferred
network. If restore logic stops as soon as any association appears, it can:

- skip the explicit reconnect to the intended SSID
- leave the machine on the wrong network
- report or behave as though restore succeeded

That is a correctness bug.

### 2. False Failure After A Correct Association

The inverse bug can also happen.

If macOS associates to the intended network but still redacts the SSID,
`wifi-wand` may be unable to prove that the network is correct even though the
radio is likely where the user wanted it to be.

That creates:

- user-visible command failures
- confusion during test cleanup
- tension between strict correctness and practical usability

### 3. Ambiguous Automation Semantics

For scripts, exit status matters.

If `connect SomeSSID` exits successfully, many callers will interpret that as:

- "the machine is now on `SomeSSID`"

Returning success when wifi-wand cannot verify that claim weakens the contract
of the command and makes automation less trustworthy.

## High-Level Policy Options

### Option A: Treat Generic Association As Good Enough

Meaning:

- if the interface is associated, return success even if the SSID is redacted

Pros:

- friendlier for interactive users
- fewer command failures when Location Services is unavailable

Cons:

- blurs the meaning of `connect`
- unsafe for restore logic
- unsafe for scripting because success no longer means "verified on requested
  SSID"

Assessment:

- unacceptable as the default policy for exact-SSID operations

### Option B: Strict Verification Everywhere

Meaning:

- if exact SSID verification is impossible, fail the operation

Pros:

- preserves strict command semantics
- safe for automation
- avoids false certainty

Cons:

- can make `connect` effectively unusable on affected macOS setups
- may feel hostile to users who intentionally run without Location Services

Assessment:

- correct for restore and test-state integrity
- arguably too rigid as the only user-facing policy for all commands

### Option C: Distinct "Degraded Success" State

Meaning:

- command returns a warning/special result when associated but unverified

Pros:

- expressive
- user-friendly
- preserves nuance

Cons:

- requires machine-readable result changes
- complicates command semantics and scripting
- easy to misuse if plain success exit codes are retained

Assessment:

- viable in theory
- larger design surface than the project needs right now

### Option D: Allow Invocation, But Refuse Identity-Sensitive Success

Meaning:

- allow the caller to invoke commands normally
- if a command fundamentally depends on exact SSID identity, raise a clear,
  targeted error instead of claiming success
- refuse unsupported test modes up front rather than partially running them

Pros:

- simple mental model
- preserves strong semantics
- avoids half-supported behavior
- gives users one obvious fix: run `wifi-wand-macos-setup`

Cons:

- more restrictive
- may block commands that occasionally would have worked through fallback paths

Assessment:

- strongest default policy
- keeps the public surface callable without weakening success semantics
- especially good for commands where exact SSID identity is the core contract

## Implementation Decision

The implemented default policy is:

1. Distinguish between generic-association operations and exact-SSID
   operations.
2. Keep exact-SSID semantics strict.
3. Allow commands/methods to be called normally.
4. When an operation depends on exact SSID identity and macOS redaction
   prevents verification, raise a targeted error instead of claiming success.
5. Refuse any requested real-environment test run up front when macOS WiFi
   identity is redacted.
6. Report the OS constraint explicitly and direct the user to
   `wifi-wand-macos-setup`.

In other words:

- do not silently degrade exact-network verification to "some network is good
  enough"
- do not blanket-disable unrelated operations that only need radio state or
  generic association
- do not hide the cause as a vague connection failure
- do tell the user that macOS is redacting WiFi identity and that the command
  cannot be completed reliably until permission is granted

## Command Classification

### Commands/Flows That Should Remain Strict

These should refuse or fail clearly when exact SSID verification is unavailable:

- `connect`
- `network_name`
- exact-network restore logic used by disruptive tests
- any future command that must answer "is the active network exactly X?"
- operations that derive security or QR data from the currently connected SSID

Why:

- their core contract is identity-sensitive
- returning success without identity proof is misleading

### Commands/Flows Whose Results Become Unavailable Or Untrustworthy

These are not exact-SSID verification commands, but they should still be
treated as affected by redaction because macOS may withhold or degrade the
network-name data they depend on:

- `avail_nets` (subcommand)
- `available_network_names` (method)
- related scan/listing output that depends on visible SSIDs

Why:

- macOS redaction is intended to prevent SSID-based location inference, not
  only to hide the currently connected network name
- scan/listing commands may therefore return redacted, incomplete, or empty
  results even when WiFi is on and association exists
- callers should not treat these commands as trustworthy sources of visible
  network identity until Location Services access has been granted

### Commands/Flows That Can Still Operate

These can continue to work with redacted SSIDs, as long as output stays honest:

- WiFi on/off
- generic association status
- disconnect
- information/status commands that can present "associated, name unavailable"
- other operations that do not require proving a particular SSID

### Real-Environment Test Runs

Requested real-environment test modes should be treated more strictly than
ordinary command invocation.

Implemented policy:

- if real-environment tests are requested on macOS
- and WiFi identity is redacted or otherwise unverifiable
- refuse the real-environment run up front with a setup error

Why:

- running only part of the requested real-environment scope implies broader
  validation than actually occurred
- disruptive tests rely on trustworthy capture/restore behavior
- failing early is clearer than running and then breaking during cleanup

This policy should apply to the real-environment test request as a whole, not
to a guessed subset of tests that might happen to be safe.

## Specific Behavior By Area

### 1. `connect`

Implemented policy:

- preserve the meaning of success as "verified on the requested SSID"
- if macOS redacts identity and exact verification is impossible, raise a
  targeted error
- explain that WiFi may be associated, but the active SSID could not be
  confirmed

Rationale:

- `connect` is frequently used in scripts
- a success exit code should stay trustworthy

### 2. `network_name` And Exact-SSID Queries

Implemented policy:

- commands and APIs whose purpose is to return or verify the current SSID
  should fail clearly when identity is redacted
- do not substitute generic association for exact SSID identity
- do not return ambiguous placeholder values as though they were usable
  answers

Examples:

- `network_name`
- `connected_network_name`
- any future `connected_to?(ssid)`-style exact-match query

Rationale:

- these operations are fundamentally about identity, not generic association
- returning anything that looks like a confirmed SSID answer would be
  misleading

### 3. Test-State Restoration

Implemented policy:

- remain strict
- if the original network cannot be verified, restoration should not silently
  pass

Rationale:

- the purpose of restore is to return the machine to its original network state
- "associated to some network" is not equivalent
- false success here can leave the test machine in an unexpected state

### 4. Real-Environment Test Entry

Implemented policy:

- do not partially run requested real-environment tests on redacted macOS
- fail the real-environment request before the suite starts
- explain that the environment is invalid for exact-network verification and
  point the user to `wifi-wand-macos-setup`

Rationale:

- "run the real env tests" should mean the requested mode ran in a valid
  environment
- partial execution would imply broader coverage than was actually obtained
- this avoids cleanup-time surprises and keeps test reporting honest

### 5. Current-Network-Derived Commands

Implemented policy:

- commands that derive output from the currently connected SSID should refuse to
  proceed when identity is redacted
- raise a targeted error explaining that the current network cannot be verified

Examples:

- QR generation for the currently connected network
- any future command that needs the actual current SSID as an input to further
  work

Rationale:

- these commands are only meaningful if the current network identity is known
- best-effort guesses would produce misleading or unsafe output

### 6. Generic Association And Status Commands

Implemented policy:

- commands that only need radio state or generic association may continue to
  operate
- they must report the limitation honestly when identity is unavailable

Examples:

- WiFi on/off
- disconnect
- `info`
- `status`

Rationale:

- these commands can still provide useful information or behavior without
  proving an exact SSID
- the output must distinguish "associated" from "current network identity is
  known"

### 7. Scan And Listing Commands

Implemented policy:

- commands that list visible networks should be documented as unavailable or
  untrustworthy under macOS redaction
- do not imply that `avail_nets` (subcommand), `available_network_names`
  (method), or similar scan/listing output remains reliable when Location
  Services permission is missing
- when possible, present the results honestly as redacted, incomplete, or
  unavailable rather than as authoritative SSID data

Examples:

- `avail_nets` (subcommand)
- `available_network_names` (method)
- related listing output derived from visible nearby SSIDs

Rationale:

- the same privacy model that hides the current SSID is intended to prevent
  location inference from surrounding SSIDs
- scan/listing results therefore should not be documented as expected to work
  meaningfully under redaction
- this is a different problem shape from exact-identity verification, but it
  still makes the command results unsuitable for trust-sensitive workflows

### 8. User-Facing Documentation

Implemented policy:

- document this as an OS-imposed limitation, not as a bug that `wifi-wand`
  should be expected to work around completely
- explain the difference between generic association and exact SSID
  verification
- list which commands become unreliable or unavailable without permission

## Why Not Compensate With Heuristics?

Several heuristics were considered:

- treating any association as success
- relying on transient placeholder SSID states
- trying to infer intent from timing windows
- weakening restore semantics to accept any associated network

These approaches were rejected as defaults because they replace a known
OS limitation with silent ambiguity. That is worse for correctness and harder to
document honestly.

If the OS will not reveal identity, `wifi-wand` should normally say:

- "I know the interface is associated"
- "I do not know which SSID it is associated with"

That is a truthful contract.

## Implemented User-Facing Messaging

For strict exact-SSID commands, the message should be explicit and actionable.

Preferred shape:

- command requires exact WiFi network identity
- macOS is redacting WiFi names because Location Services is not enabled for
  `wifiwand-helper`
- run `wifi-wand-macos-setup` and grant permission, then retry

The current error wording already moves in this direction and should continue to
be refined for clarity, but the key requirement is consistency:

- do not imply that the password or target SSID was wrong
- do not imply that the radio is necessarily disconnected
- do make the OS permission problem obvious

For real-environment test refusal, the message should be even more direct:

- real-environment tests were requested
- macOS is redacting WiFi identity, so exact-network verification and restore
  are not trustworthy
- run `wifi-wand-macos-setup`, grant Location Services, then rerun the tests

## Relationship To Existing Changes

This policy note records the implementation direction taken in two related
change tracks:

1. restore-path fixes that prevent macOS auto-reassociation to the wrong
   preferred network from being treated as successful restore
2. redaction-aware reporting that explains when wifi-wand cannot verify the
   requested/original SSID because macOS is withholding identity

Those changes address immediate correctness and diagnostics. This document
captures the broader default policy they now implement.

## Follow-Up Work

1. Audit commands and APIs for whether they are generic-association or
   exact-SSID operations.
2. Ensure identity-sensitive commands raise targeted redaction errors rather
   than generic failures.
3. Keep restore strict.
4. Preserve the preflight gate that refuses any requested real-environment test
   run on macOS when WiFi identity is redacted.
5. Keep end-user docs clear that modern macOS without Location Services should
   be treated as unsupported for exact-SSID workflows.
6. Avoid introducing best-effort success semantics unless the project later adds
   a clearly distinct degraded-success API/CLI contract.

## Bottom Line

The real issue is not whether `wifi-wand` can detect that WiFi is "sort of
working." The issue is whether it can honestly verify network identity.

When macOS redacts SSIDs, `wifi-wand` should keep ordinary non-identity
operations available, raise truthful targeted errors for identity-sensitive
operations, and refuse real-environment test runs that depend on trustworthy
network identity. That keeps command semantics coherent, protects automation,
and makes the remediation path clear.
