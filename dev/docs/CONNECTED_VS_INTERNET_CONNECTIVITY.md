# `connected?` vs `internet_connectivity_state`

## Purpose

This note documents the current semantic split between `connected?` and
`internet_connectivity_state`, why the distinction feels awkward in practice,
and which simplifications are worth considering later.

## Short Version

- `connected?` answers a WiFi-layer question.
- `internet_connectivity_state` answers an internet-reachability question.
- Both are useful.
- The current API surface makes their relationship harder to understand than it
  should be.

## Current Meanings

### `connected?`

`connected?` is the WiFi model's notion of whether the WiFi interface is
connected or otherwise usable.

It is intentionally not the same as "this machine has network access by any
route."

Practical consequences:

- Ethernet-only internet access does not imply `connected? == true`.
- `connected?` may be `true` even when the SSID is unavailable or redacted.
- `connected?` is broader than `associated?` on macOS.

### `internet_connectivity_state`

`internet_connectivity_state` answers a different question: is the internet
reachable, unreachable, or genuinely indeterminate?

It combines:

- TCP reachability
- DNS resolution
- Captive-portal detection

It is explicitly host-level and can report reachable internet even when WiFi is
off or when another uplink, such as Ethernet, is active.

## Nearby Concept: `associated?`

Although this document focuses on two APIs, `associated?` matters because it
helps explain why `connected?` causes confusion.

- `associated?` is SSID / access-point association state.
- `connected?` is WiFi usability state.
- `internet_connectivity_state` is host internet state.

Those are three different layers. The codebase mostly benefits from keeping
them separate.

## Where Each Is Used Today

### `connected?`

`connected?` is primarily a model-level method.

Observed uses include:

- connection readiness and `ip_address` guards in `BaseModel`
- network identity in `StatusLineDataBuilder`
- connection-change logging in `EventLogger`
- OS-specific connection logic in `MacOsModel` and `UbuntuModel`

It is not currently delegated on `WifiWand::Client`, so library consumers do
not call `client.connected?`. They would need `client.model.connected?`.

### `internet_connectivity_state`

`internet_connectivity_state` is part of the public high-level API.

Observed uses include:

- `WifiWand::Client`
- the `ci` command
- `status`
- `info`
- `StatusWaiter` for `internet_on` / `internet_off`
- event logging

This method is already the explicit public replacement for the removed
`connected_to_internet?` API.

## Why This Feels Off

### 1. The word `connected` is overloaded

In normal English, "connected" often means "has network access." In this
project, `connected?` means something narrower and more WiFi-specific.

That is defensible, but surprising.

### 2. The public API is asymmetric

`internet_connectivity_state` is part of `WifiWand::Client`, but `connected?`
is not. That creates an odd split:

- one connectivity concept is public and explicit
- the other is real and important, but mostly internal / model-facing

### 3. The CLI exposes one clearly and the other indirectly

There is a dedicated `ci` command for internet state, but no equally explicit
CLI surface for "WiFi connected?" as a first-class concept.

Instead, that concept leaks through `status`, `log`, and internal behavior.

### 4. macOS makes the distinction more visible

On macOS, `connected?` is intentionally broader than `associated?`. That is
useful, but it makes it even easier for readers to assume `connected?` is an
internet-level predicate when it is not.

## What Should Not Be Done

### Do not redefine `connected?` to mean host connectivity

That would collapse two distinct layers into one method and make WiFi behavior
harder to reason about.

Problems that would follow:

- WiFi-specific flows could report "connected" while WiFi is off
- connection and disconnection semantics would become muddier
- tests would need to separate WiFi state from host uplink state everywhere
- the method name would stop matching many current call sites

For this project, that would likely increase confusion rather than reduce it.

## Recommended Direction

### Recommendation 1: Keep the semantic split

Retain the distinction between:

- `associated?`
- `connected?`
- `internet_connectivity_state`

These represent different layers and should stay different.

### Recommendation 2: Make the layering explicit in docs

The docs should keep stating that:

- `associated?` is WiFi association
- `connected?` is WiFi connection / usability
- `internet_connectivity_state` is host internet reachability

This is the lowest-risk improvement and has already started in the user docs.

### Recommendation 3: Consider a better public name for WiFi usability

If the maintainer wants to reduce ambiguity in a future release, consider
introducing a clearer alias for `connected?`, such as:

- `wifi_connected?`
- `wifi_usable?`
- `link_connected?`

Of those, `wifi_connected?` is the clearest to users, even if it is somewhat
redundant.

A pragmatic migration path would be:

1. Add `wifi_connected?` as an alias of `connected?`
2. Use the clearer name in docs and new code
3. Keep `connected?` for backward compatibility unless there is a major-version
   reason to deprecate it

### Recommendation 4: Decide whether `connected?` should become public

There are two reasonable choices:

- Keep it internal-ish and document it as model-level only
- Promote it to `WifiWand::Client` as an explicitly WiFi-scoped predicate

Either choice is better than the current in-between state.

My preference is to expose it publicly only if it gets a clearer name such as
`wifi_connected?`.

### Recommendation 5: Consider a CLI command only if it has a strong use case

A dedicated CLI command for WiFi connection state is not obviously necessary.
`status` already shows the concept in context.

A new command is only worth adding if users need a single machine-readable WiFi
state value for scripting, distinct from internet reachability.

## Suggested Maintainer Decision

If no behavioral change is desired soon, the cleanest path is:

1. Keep runtime behavior as-is
2. Keep `connected?` WiFi-specific
3. Keep `internet_connectivity_state` host-level
4. Improve docs
5. Optionally add a clearer alias later

If a future API cleanup is planned, the best simplification is probably naming,
not semantics.

## Bottom Line

The smell is real, but the underlying distinction is valid.

The main problem is not that both APIs exist. The problem is that `connected?`
is named broadly, exposed unevenly, and easy to misread as an internet
predicate.

The most promising simplification is to keep the current behavior and improve
the API vocabulary around the WiFi-specific concept.
