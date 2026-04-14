# Refactor Prompt: Make macOS Helper Results Explicit Instead of Side-Effect Driven

## Context

The current macOS helper integration has a design smell in the Ruby layer:

- `WifiWand::MacOsWifiAuthHelper::Client#scan_networks` returns network data or an empty/nil-like result
- separate methods such as `location_services_blocked?` infer state from `@last_error_message`
- callers must invoke a helper method first and then inspect side state afterward

That creates an opaque coupling in code such as:

```ruby
networks = mac_helper_client.scan_networks
return [] if mac_helper_client.location_services_blocked?
return nil unless networks&.any?
```

This works, but it is harder to read and reason about because:

1. Call ordering matters implicitly
2. State from one call can affect later interpretation
3. The method contract is incomplete unless the caller also knows to inspect side state
4. Tests must understand implementation details rather than a clean public result contract

The goal of this refactor is to replace that pattern with an explicit return value that contains both data and
status.

## Goal

Refactor the macOS helper client so helper query methods return a single explicit result object/value
containing:

- the requested payload
- whether Location Services blocked the query
- any error message relevant to caller behavior

The calling model code should branch only on the returned result, not on hidden client state.

## Desired Outcome

After the refactor, code in `MacOsModel` should look conceptually like this:

```ruby
result = mac_helper_client.scan_networks
return [] if result.location_services_blocked?
return nil unless result.networks.any?

...
```

or, if a hash is used:

```ruby
result = mac_helper_client.scan_networks
return [] if result[:location_services_blocked]
return nil unless result[:networks].any?
```

The important part is that all information needed to interpret the helper call is returned together.

## Scope

Focus only on the Ruby-side contract between:

- `lib/wifi-wand/mac_os_wifi_auth_helper.rb`
- `lib/wifi-wand/models/mac_os_model.rb`

Do not expand this change into a larger architectural rewrite unless required.

Do not change the higher-level product behavior beyond preserving current intent:

- explicit Location Services failures should not fall back to redacted `system_profiler` output
- placeholder SSIDs such as `<hidden>` and `<redacted>` should remain filtered
- callers should still be able to distinguish:
  - successful helper data
  - helper unavailable or generic failure
  - Location Services blocked/denied/timed out

## Recommended Design

Choose the simplest explicit contract that fits the existing codebase. Prefer one of these:

### Option A: Small result struct

Introduce a small immutable value object, for example:

```ruby
HelperQueryResult = Struct.new(
  :payload,
  :location_services_blocked,
  :error_message,
  keyword_init: true
)
```

Then add convenience readers if helpful for scan/current-network use cases.

Pros:

- explicit and self-documenting
- cleaner call sites
- easier to test
- avoids stringly-typed hashes everywhere

### Option B: Plain hash

Return a hash such as:

```ruby
{
  payload: ...,
  location_services_blocked: true/false,
  error_message: '...'
}
```

Pros:

- minimum ceremony
- likely smallest patch

Cons:

- less self-documenting
- easier to misuse

If both are equally easy, prefer the struct/value-object approach.

## Concrete Refactor Tasks

1. Update helper client public query methods so they return explicit result values

Likely methods:

- `connected_network_name`
- `scan_networks`

You may also choose to introduce lower-level explicit result methods and keep convenience wrappers if that
makes migration easier.

2. Remove or reduce hidden side-state reliance

Specifically review:

- `@last_error_message`
- `location_services_blocked?`

If possible, remove `location_services_blocked?` entirely from the public contract. If it must remain
temporarily for compatibility, make it a thin adapter over the new result shape and mark it as transitional in
comments.

3. Update `MacOsModel` to use the explicit result contract

At minimum review:

- `helper_available_network_names`
- `_connected_network_name`

The model should no longer need to query hidden helper-client state after calling a helper method.

4. Preserve current behavior

Keep these semantics:

- if Location Services blocked the helper scan, do not fall back to `system_profiler`
- if helper returns usable SSIDs, use them
- if helper simply has no data for a non-auth reason, preserve current fallback behavior where appropriate

5. Update tests

Revise specs so they assert against the explicit result contract rather than side effects.

Relevant files:

- `spec/wifi-wand/mac_os_wifi_auth_helper_spec.rb`
- `spec/wifi-wand/models/mac_os_model_spec.rb`

## Testing Expectations

Run targeted tests first:

```bash
bundle exec rspec spec/wifi-wand/mac_os_wifi_auth_helper_spec.rb
bundle exec rspec spec/wifi-wand/models/mac_os_model_spec.rb
bundle exec rspec spec/wifi-wand/command_line_interface_spec.rb
```

If behavior shifts in user-facing output, update specs accordingly.

## Constraints

- Keep the patch focused on this contract cleanup
- Do not revert unrelated local changes
- Do not introduce new gems
- Preserve existing macOS behavior around helper installation and explicit Location Services errors
- Prefer clear contracts over clever abstractions

## Acceptance Criteria

The refactor is successful if:

1. No model code depends on calling one helper method and then separately reading hidden helper-client state
   to understand the result
2. The helper client’s public query contract is explicit about payload and authorization failure status
3. Existing behavior around suppressing redacted fallback remains intact
4. Targeted specs pass
5. The resulting code is easier to read than the current `scan -> inspect side state` flow

## Non-Goals

- Reworking the Swift helper JSON schema unless necessary
- Adding new user-facing commands
- Solving stale installed helper upgrade behavior
- Redesigning the entire macOS helper subsystem

## Suggested Commit Message

If this refactor is implemented as a standalone commit, a reasonable message would be:

```text
Make macOS helper query results explicit in Ruby client
```
