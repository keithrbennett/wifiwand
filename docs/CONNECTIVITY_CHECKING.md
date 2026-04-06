# Connectivity Checking

## Overview

The `ci` command (connectivity info) is the primary tool for checking internet connectivity. It provides a simple true/false indication of whether TCP connectivity, DNS resolution, and captive-portal-free internet access are working.

## Basic Usage

Check if internet is available:

```bash
wifi-wand ci
```

Output:
```
Connected to Internet: true
```

Or if not connected:
```
Connected to Internet: false
```

## Using in Scripts

The `ci` command is specifically designed for use in shell scripts where you need a simple connectivity check:

```bash
#!/bin/bash
# Check if internet is available before proceeding
if wifi-wand ci | grep -q true; then
  echo "Internet is available - proceeding with upload"
  # Do something that requires internet
  curl https://example.com/upload --data @file.txt
else
  echo "Internet is unavailable - will retry later"
  # Queue the operation for later
  exit 1
fi
```

### Exit Codes for Automation

You can also use the exit code (though the above pattern with grep is simpler):

```bash
#!/bin/bash
# Retry operation until internet is available
while ! wifi-wand ci | grep -q true; do
  echo "Waiting for internet..."
  sleep 10
done

echo "Internet is now available!"
# Proceed with network operations
```

## Comparing Connectivity Tools

| Command | Use Case | Output | Speed |
|---------|----------|--------|-------|
| `ci` | Simple connectivity check | true/false | Fast |
| `status` | Full network summary | Multi-field status | Several seconds |
| `info` | Detailed network info | Complete data | Several seconds |

Use `ci` when you just need to know "is the internet working?". Use `status` when you need the complete picture of your network state.

## Understanding the Results

`ci` checks three things:

1. **DNS Resolution**: Can the system resolve domain names?
2. **TCP Connectivity**: Can the system establish TCP connections?
3. **Captive Portal Detection**: If TCP and DNS work, does an HTTP connectivity-check endpoint return the expected status code rather than a portal redirect or login page?

Internet is considered available only when all required checks pass.

## Examples

### Wait for Internet to Come Back Online

```bash
#!/bin/bash
echo "Internet went down, waiting for it to come back..."

while ! wifi-wand ci | grep -q true; do
  sleep 5
done

echo "Internet is back!"
mail -s "Internet restored" user@example.com < /dev/null
```

### Run a Task Only When Internet is Available

```bash
#!/bin/bash

if wifi-wand ci | grep -q true; then
  # Do something that requires internet
  git push origin main
  echo "Code pushed successfully"
else
  echo "No internet - skipping push"
  exit 1
fi
```

### Monitor Connectivity in a Loop

```bash
#!/bin/bash

while true; do
  if wifi-wand ci | grep -q true; then
    echo "$(date): Internet available"
  else
    echo "$(date): Internet unavailable"
  fi
  sleep 30
done
```

## Timeouts

Like the `status` command, `ci` uses intentionally long timeouts (several seconds on macOS) to avoid false positives from temporary network slowdowns. This means each check takes several seconds to complete.

If you need to check connectivity frequently, be mindful that each check will block for several seconds. Use appropriate sleep intervals between checks when polling in a loop.

## Captive Portal Detection

Beyond basic TCP and DNS checks, wifi-wand can detect **captive portals** — the
interception pages common in coffee shops, hotels, and airports that block real
internet access behind a login screen.

### How It Works

Captive portals intercept TCP connections and complete the handshake on behalf of
external hosts. This makes plain TCP connectivity checks unreliable —
`tcp_connectivity?` returns `true` even when real internet access is blocked.

The `captive_portal_free?` method disambiguates by issuing real HTTP GET requests
to well-known connectivity check endpoints (e.g. Google's `generate_204` endpoints)
and verifying the response status codes. A `204 No Content` response can only come
from the actual server — captive portals return `302` redirects or `200` HTML login
pages instead.

**HTTP (not HTTPS) is used intentionally:** captive portals must respond to plain
HTTP requests themselves rather than silently forwarding them, which forces a
detectable status code mismatch.

### Terminology: "mismatch"

A **mismatch** means an endpoint returned an HTTP status code different from the
expected code configured for that endpoint (e.g. receiving a `302` or `200` when
`204` was expected). This is distinct from a **network error** (timeout, connection
refused, DNS failure), which produces no HTTP response at all.

A mismatch is significant because it indicates the server *did* respond, but with
unexpected content — the hallmark of a captive portal intercepting and rewriting
the request. However, a single mismatch is not conclusive on its own (the endpoint
could have been reconfigured or temporarily misbehaving), so the method continues
checking remaining endpoints before making a final determination.

### Endpoint Redundancy

Multiple endpoints are checked concurrently so that a single misbehaving or
rewritten endpoint cannot cause a false captive-portal detection without adding
serial worst-case timeout cost:

- If **any** endpoint returns the expected status code, the method returns `true`
  (real internet confirmed).
- If an endpoint returns an unexpected HTTP status code, the method records a
  "definite mismatch" but continues trying remaining endpoints in case one of them
  succeeds.
- If an endpoint fails with a network-level error, the method skips it and moves
  on — the endpoint server itself may be unreachable, which does not indicate a
  captive portal.

### Return Values

| Return | Condition | Meaning |
|--------|-----------|---------|
| `true` | At least one endpoint returned the expected status code | Real internet confirmed |
| `false` | At least one endpoint returned a wrong status code **and** none succeeded | Captive portal detected |
| `true` | All endpoints failed with network errors, none returned any HTTP response | Can't determine; assume free to avoid false negatives |

The "assume free" fallback for all-network-error scenarios avoids false negatives
that would falsely report captive-portal detection on networks with transient
connectivity issues (e.g. the check servers themselves being temporarily
unreachable).

### Decision Flow

For each endpoint:

1. Attempt HTTP GET via `attempt_captive_portal_check`.
   - Returns `true` → expected code received; mark internet confirmed.
   - Returns `false` → wrong code received (mismatch); record it.
   - Returns `nil` → network error; ignore it for mismatch purposes.

After the concurrent checks complete:

- If any endpoint succeeded → return `true`.
- Otherwise, if any mismatch was recorded → return `false` (captive portal detected).
- Otherwise → return `true` (all errors, assume free).

### Verbose Logging

When verbose mode is enabled (`wifi-wand -v`), the method logs:

- The list of endpoints being tested before the first request.
- Per-endpoint results: `pass`, `mismatch`, or network error details.
- A final decision message indicating the outcome.

### Deferred Checking in `wifi_info`

The `wifi_info` method (used by the `info` command) defers the captive portal
HTTP check when TCP or DNS has already failed. Since a captive portal can only
be present when both TCP and DNS are working (portals complete TCP handshakes
and provide DNS), performing the HTTP request on an obviously-offline network
adds unnecessary delay. When TCP or DNS is `false`, `captive_portal_free` is
set to `true` without making any HTTP request.
