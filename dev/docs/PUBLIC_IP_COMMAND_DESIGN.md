# `public_ip` Command Architecture

## Purpose

The `public_ip` command provides an explicit interface for retrieving public IP
metadata without overloading `info`.

This keeps `info` focused on local and directly observable network state while
making external public-IP lookup an intentional command.

## Relationship To `info`

`info` no longer returns `public_ip`.

That separation is intentional:

- `info` reports local network diagnostics and state
- `public_ip` reports externally derived metadata
- `info` no longer incurs hidden latency from third-party lookups
- the public IP feature is easier to test and document as a dedicated command

## Command Names And Aliases

Canonical command:

```text
public_ip
```

Short alias:

```text
pi
```

The command accepts one optional selector argument. Users can mix the long and
short command names with the long and short selectors. For example, all of the
following are valid:

```bash
wifi-wand public_ip
wifi-wand public_ip address
wifi-wand public_ip a
wifi-wand pi
wifi-wand pi country
wifi-wand pi c
```

## Selector Behavior

Supported selectors:

- `address` or `a`
- `country` or `c`
- `both` or `b`

Default selector:

- `both`

Selector behavior maps directly to the current model API:

- `address` / `a` calls `public_ip_address`
- `country` / `c` calls `public_ip_country`
- `both` / `b` calls `public_ip_info`

## Human-Readable Output

Human-readable output stays narrow and stable.

For `address`:

```text
Public IP Address: 203.0.113.5
```

For `country`:

```text
Public IP Country: TH
```

For `both`:

```text
Public IP Address: 203.0.113.5  Country: TH
```

`both` is rendered as a single line. The labels are the same for IPv4 and IPv6.

## Machine-Readable Output

The command uses the existing `-o` output pipeline.

Return shapes are intentionally small:

- `address` returns a string containing the public IP address
- `country` returns a string containing the ISO alpha-2 country code
- `both` returns a hash with `address` and `country`

Example `both` shape:

```json
{
  "address": "203.0.113.5",
  "country": "TH"
}
```

The object key is `address`, not `ip`, so the machine-readable shape matches the
CLI vocabulary.

## IPv4 And IPv6 Support

The command accepts both IPv4 and IPv6 responses.

`BaseModel` validates public IP values with `IPAddr`, which avoids IPv4-only
assumptions. Human-readable labels and machine-readable field names do not vary
by address family.

Examples of valid addresses include:

- `203.0.113.5`
- `2001:db8::1`

## Provider Strategy

The current provider strategy is selector-specific:

- `address` / `a` uses `ipify`
- `country` / `c` uses `country.is`
- `both` / `b` uses `country.is`

This keeps the address-only path lightweight while letting `country` and `both`
reuse the single response from `country.is`, which already returns both the
caller IP and country code.

Relevant provider behavior:

- `ipify` is used for IP-only lookups
- `country.is` returns JSON with `ip` and `country`
- `country.is` may rate limit and return `429`

## Internal Model API

The command currently uses these `BaseModel` methods:

- `public_ip_info`
- `public_ip_address`
- `public_ip_country`

Current behavior:

- `public_ip_info` calls `country.is` and returns
  `{ 'address' => ..., 'country' => ... }`
- `public_ip_address` calls `ipify` and returns the address string
- `public_ip_country` delegates to `public_ip_info` and returns the country code

This keeps the `address` path fast and avoids duplicate lookups for `country`
and `both`.

## Error Handling Model

`public_ip` is explicitly dependent on external services, so failures are
surfaced directly as `PublicIPLookupError`.

Current behavior:

- lookups use a short timeout
- foreground lookups do not retry
- `429` is reported as rate limiting
- malformed provider responses raise a malformed-response error
- timeout-family failures raise a timeout error
- transport failures are normalized to `Public IP lookup failed: network error`
- non-success HTTP responses preserve the HTTP status in the message

Examples of current user-facing messages include:

```text
Public IP lookup failed: timeout
Public IP lookup failed: rate limited
Public IP lookup failed: malformed response
Public IP lookup failed: network error
Public IP lookup failed: HTTP 500 Internal Server Error
```

Verbose mode preserves structured context on the exception object and prints it
through the CLI verbose error path.

## Breaking Change

This feature includes an intentional breaking change:

- `info` no longer returns `public_ip`
- callers that previously depended on `info["public_ip"]` must switch to the
  `public_ip` or `pi` command
- the new command returns a narrower data shape than the old unauthenticated
  IPinfo response

That narrowing is intentional. The current feature only exposes the fields that
wifi-wand uses today: public address and country code.

## Non-Goals And Out Of Scope

The current architecture intentionally does not include:

- caching
- provider / ISP enrichment

Those remain out of scope because they add persistence, privacy, or latency
concerns without improving the core command contract.

## Help And Invalid Selectors

Help text documents both command names and both selector forms.

Invalid selectors raise a clear configuration error:

```text
Invalid selector 'x'. Use one of: address (a), country (c), both (b).
```
