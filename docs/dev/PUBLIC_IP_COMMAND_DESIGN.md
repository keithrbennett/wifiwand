# `public_ip` Command Design

## Purpose

This document captures the agreed design for a new dedicated command that
retrieves public IP information without overloading the existing `info`
command.

The goal is to keep `info` focused on local and directly observable network
state, while moving externally derived public-IP metadata into an explicit
command that users invoke intentionally.

## Background

The existing `info` command included public IP lookup logic. That created a
few design problems:

- `info` mixed local network diagnostics with externally derived metadata
- public IP lookup depended on a third-party service
- the lookup could introduce avoidable latency into a common command
- the public IP country was more valuable than the address itself, but both
  still required an external lookup

We considered several alternatives, including:

- keeping public IP lookup in `info` behind a flag
- caching previous public IP to country mappings
- using lighter-weight IP-only lookups first and geo lookups second

The chosen direction is simpler:

- remove public IP information from `info`
- add a dedicated command for public IP information
- support retrieving address, country, or both
- do not add caching yet

## Scope

This design covers:

- command names
- selector syntax
- human-readable output
- machine-readable output
- default behavior
- error handling expectations

This design does not yet cover:

- the exact provider implementation
- caching or persistence
- whether the provider returns country code only or extra metadata

## Command Names

Canonical command:

```text
public_ip
```

Short alias:

```text
pi
```

Examples:

```bash
wifi-wand public_ip
wifi-wand public_ip address
wifi-wand public_ip country
wifi-wand public_ip both

wifi-wand pi
wifi-wand pi a
wifi-wand pi c
wifi-wand pi b
```

## Selectors

The command accepts one optional selector argument.

Supported selectors:

- `address`
- `country`
- `both`

Supported abbreviated selectors:

- `a` => `address`
- `c` => `country`
- `b` => `both`

Default selector:

- `both`

Examples:

```bash
wifi-wand public_ip
wifi-wand public_ip both
wifi-wand public_ip address
wifi-wand public_ip country
wifi-wand pi a
wifi-wand pi c
wifi-wand pi b
```

## Country Representation

Country should be represented using the ISO 3166-1 alpha-2 country code.

Examples:

- `US`
- `TH`
- `GB`

Rationale:

- short and script-friendly
- stable and easy to compare
- enough for the current use case

The initial design does not require full country names such as `Thailand`.

## Human-Readable Output

The human-readable strings should be:

For `address`:

```text
Public IP Address: a.b.c.d
```

For `country`:

```text
Public IP Country: TH
```

For `both`:

```text
Public IP Address: a.b.c.d  Country: TH
```

Notes:

- `both` should be a single line in human-readable mode
- the wording should stay exactly aligned with the selector names where
  practical

## Machine-Readable Output

Existing `-o` output formatting should continue to apply.

Recommended return values:

For `address`:

- return the address string

For `country`:

- return the country code string

For `both`:

- return a hash/object with:

```json
{
  "address": "a.b.c.d",
  "country": "TH"
}
```

Rationale:

- the string forms are convenient for scripts
- the object form is explicit and easy to serialize to JSON or YAML
- `address` is preferred over `ip` in the object because it matches the
  command vocabulary more clearly

## Relationship To `info`

`info` should no longer include public IP information.

Rationale:

- public IP and country are externally derived, not purely local state
- this avoids hidden latency in `info`
- the command boundary becomes clearer
- the feature becomes easier to test and document

This means:

- remove `public_ip` lookup from `wifi_info`
- remove any `--public-ip` flag added for `info`
- make `public_ip` the sole command for this feature

## Internal Model API

The CLI command should delegate to one model/service method that returns both
address and country in a single call.

Proposed method name:

```ruby
public_ip_info
```

Proposed return shape:

```ruby
{ 'address' => 'a.b.c.d', 'country' => 'TH' }
```

The command layer then selects:

- `address`
- `country`
- or the full hash

This is preferred over separate address and country calls because it:

- avoids multiple external lookups
- keeps the CLI code simpler
- preserves flexibility for provider changes later

## Error Handling

This command is explicit and externally dependent, so failures can be surfaced
directly rather than hidden.

Expected behavior:

- use a short timeout
- do not retry in the foreground path
- raise a clear user-facing error when lookup fails

Example error text:

```text
Public IP lookup failed: timeout
```

or, if a more general message is preferred:

```text
Could not retrieve public IP information
```

The final wording can be decided during implementation, but the command should
fail clearly rather than silently inventing partial data.

## No Caching For Initial Version

Caching is intentionally out of scope for the first implementation.

Reasoning:

- it adds persistence and invalidation logic
- it introduces privacy questions around retained public IP history
- it is not necessary to validate the command design

If needed later, caching can be added behind the same command contract without
changing the CLI interface.

## Help Text Expectations

Help output should document:

- `public_ip` as the canonical command
- `pi` as a short alias
- selectors:
  - `address (a)`
  - `country (c)`
  - `both (b)`
- default selector:
  - `both`

Example help text shape:

```text
public_ip [address|country|both]
pi        [a|c|b]
```

## Invalid Selector Behavior

Invalid selectors should produce a clear error message.

Recommended message:

```text
Invalid selector 'x'. Use one of: address (a), country (c), both (b).
```

## Examples

Human-readable:

```bash
wifi-wand public_ip
wifi-wand public_ip address
wifi-wand public_ip country
wifi-wand pi c
```

Machine-readable:

```bash
wifi-wand -o j public_ip
wifi-wand -o p public_ip address
wifi-wand -o y public_ip country
```

## Implementation Checklist

Planned implementation steps:

1. Remove public IP lookup from `wifi_info`.
2. Remove any `--public-ip` option related to `info`.
3. Add a model/service method for retrieving public IP info in one call.
4. Add `cmd_public_ip(selector = 'both')`.
5. Add command aliases:
   - `public_ip`
   - `pi`
6. Add selector parsing for:
   - `address` / `a`
   - `country` / `c`
   - `both` / `b`
7. Add help text.
8. Add specs for:
   - default `both`
   - `address`
   - `country`
   - abbreviated selectors
   - invalid selector
   - machine-readable output

## Summary

The chosen design is:

- move public IP lookup out of `info`
- add a dedicated `public_ip` command
- add short alias `pi`
- support selectors:
  - `address` / `a`
  - `country` / `c`
  - `both` / `b`
- default to `both`
- use country codes such as `TH`
- no caching in the first version

This keeps the feature explicit, simple, and easy to refine later.
