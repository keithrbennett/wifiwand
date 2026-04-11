# Connectivity Checking

## Overview

The `ci` command (connectivity info) is the primary CLI for checking the current
internet-connectivity state.

In this major release, `ci` no longer exposes a boolean result. It now reports
one of three explicit states:

- `reachable`
- `unreachable`
- `indeterminate`

This matches the library API `internet_connectivity_state`, which returns the
same values as Ruby symbols:

- `:reachable`
- `:unreachable`
- `:indeterminate`

## Breaking Change and Migration

The old boolean-style API `connected_to_internet?` has been removed.

| Old | New |
|-----|-----|
| `connected_to_internet? == true` | `internet_connectivity_state == :reachable` |
| `connected_to_internet? == false` | `internet_connectivity_state == :unreachable` |
| `connected_to_internet? == nil` | `internet_connectivity_state == :indeterminate` |

Library example:

```ruby
case client.internet_connectivity_state
when :reachable
  upload_file
when :unreachable
  queue_retry
when :indeterminate
  warn 'Connectivity state unknown; retry later'
end
```

Shell example:

```bash
if [ "$(wifi-wand -o p ci)" = "reachable" ]; then
  echo "Internet reachable"
fi
```

JSON/JQ example:

```bash
if wifi-wand -o j ci | jq -e '. == "reachable"' > /dev/null; then
  echo "Internet reachable"
fi
```

## Basic Usage

```bash
wifi-wand ci
```

Human-readable output:

```text
Internet connectivity: reachable
```

Other possible outputs:

```text
Internet connectivity: unreachable
Internet connectivity: indeterminate
```

For scripts, prefer a machine-readable format:

```bash
wifi-wand -o p ci
wifi-wand -o j ci
```

Examples:

```text
reachable
```

```json
"reachable"
```

## What the States Mean

| State | Meaning |
|-------|---------|
| `reachable` / `:reachable` | Internet reachability is confirmed |
| `unreachable` / `:unreachable` | Internet is known to be unavailable |
| `indeterminate` / `:indeterminate` | The result is genuinely unknown |

### What `indeterminate` Means

`indeterminate` is not a special kind of `unreachable`.

It means:

- TCP connectivity succeeded
- DNS resolution succeeded
- but captive-portal checks could not determine whether the network is truly
  open Internet or an intercepted login network

So an indeterminate state may still correspond to a network that is actually
reachable. It is reported separately because a boolean API would imply false
certainty.

## Using in Scripts

Check whether connectivity is confirmed:

```bash
#!/bin/bash

state="$(wifi-wand -o p ci)"

if [ "$state" = "reachable" ]; then
  echo "Internet is available - proceeding with upload"
  curl https://example.com/upload --data @file.txt
elif [ "$state" = "indeterminate" ]; then
  echo "Internet state is unknown - avoiding a false claim either way"
  exit 2
else
  echo "Internet is unavailable - will retry later"
  exit 1
fi
```

Wait for internet to come back:

```bash
#!/bin/bash
echo "Internet went down, waiting for it to come back..."

while [ "$(wifi-wand -o p ci)" != "reachable" ]; do
  sleep 5
done

echo "Internet is back!"
```

Monitor connectivity in a loop:

```bash
#!/bin/bash

while true; do
  state="$(wifi-wand -o p ci)"

  if [ "$state" = "reachable" ]; then
    echo "$(date): Internet available"
  elif [ "$state" = "indeterminate" ]; then
    echo "$(date): Internet state unknown"
  else
    echo "$(date): Internet unavailable"
  fi

  sleep 30
done
```

## Comparing Connectivity Tools

| Command | Use Case | Output | Speed |
|---------|----------|--------|-------|
| `ci` | Single explicit connectivity state | reachable/unreachable/indeterminate | Several seconds |
| `status` | Full network summary | Multi-field status | Several seconds |
| `info` | Detailed network info | Complete data | Several seconds |

Use `ci` when you want the current connectivity state as one value. Use `status`
or `info` when you need the full network picture.

## How Connectivity Is Determined

`internet_connectivity_state` combines three checks:

1. **TCP connectivity**: can the system establish TCP connections?
2. **DNS resolution**: can the system resolve domain names?
3. **Captive-portal detection**: if TCP and DNS work, do known HTTP
   connectivity-check endpoints return the expected response codes?

Internet is considered `reachable` only when all required checks pass.

## Captive Portal Detection

Beyond basic TCP and DNS checks, wifi-wand can detect **captive portals**: the
interception pages common in hotels, airports, and coffee shops that block real
internet access behind a login screen.

### Companion API: `captive_portal_state`

The captive-portal API is now explicit too:

| State | Meaning |
|-------|---------|
| `:free` | No captive portal detected |
| `:present` | Captive portal detected |
| `:indeterminate` | Captive-portal state could not be determined |

### How It Works

Captive portals intercept TCP connections and complete the handshake on behalf
of external hosts. This makes plain TCP connectivity checks unreliable:
`tcp_connectivity?` can return `true` even when real internet access is blocked.

The `captive_portal_state` method disambiguates by issuing real HTTP GET
requests to well-known connectivity-check endpoints (for example Google's
`generate_204` endpoints) and verifying the response status codes. A `204 No
Content` response can only come from the actual server. Captive portals return
redirects or login pages instead.

HTTP, not HTTPS, is used intentionally: captive portals must respond to plain
HTTP requests themselves rather than silently forwarding them.

### Endpoint Redundancy

Multiple endpoints are checked concurrently so that a single misbehaving or
rewritten endpoint cannot cause a false captive-portal detection without adding
serial worst-case timeout cost:

- If any endpoint returns the expected status code, the result is `:free`
- If an endpoint returns an unexpected status code, the method records a
  mismatch and keeps checking
- If an endpoint fails with a network-level error, the method skips it

### Return Values

| Return | Condition | Meaning |
|--------|-----------|---------|
| `:free` | At least one endpoint returned the expected status code | No captive portal detected |
| `:present` | At least one endpoint returned a wrong status code and none succeeded | Captive portal detected |
| `:indeterminate` | All endpoints failed with network errors | Captive-portal state could not be determined |

## How `internet_connectivity_state` Is Derived

The higher-level `internet_connectivity_state` API combines TCP, DNS, and
captive-portal state into an explicit symbolic result:

| TCP | DNS | Captive portal | Internet connectivity |
|-----|-----|----------------|-----------------------|
| pass | pass | `:free` | `:reachable` |
| fail | any | any | `:unreachable` |
| any | fail | any | `:unreachable` |
| pass | pass | `:present` | `:unreachable` |
| pass | pass | `:indeterminate` | `:indeterminate` |

## Deferred Checking in `wifi_info`

The `wifi_info` method (used by the `info` command) skips the captive-portal
HTTP check when TCP or DNS has already failed. Since a captive portal can only
be present when both TCP and DNS are working, performing the HTTP request on an
obviously offline network adds unnecessary delay.

When TCP or DNS is `false`, `captive_portal_state` is set to `:indeterminate`
without making any HTTP request.
