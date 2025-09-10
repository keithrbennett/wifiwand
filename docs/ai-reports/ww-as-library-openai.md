# WifiWand as a Library: Assessment and Recommendations

## Strengths

- Clear namespacing and entrypoint: `WifiWand.create_model` returns an OS‑specific model behind a consistent API.
- OS abstraction: `OperatingSystems` cleanly detects macOS/Ubuntu and instantiates the right model; adding OS support is straightforward via `BaseOs`.
- Rich, rescue‑able error taxonomy: all errors live under `WifiWand::Error` with helpful, user‑facing messages.
- Good separation of concerns: CLI, models, and services (`CommandExecutor`, `NetworkConnectivityTester`, `StatusWaiter`, `ConnectionManager`, `NetworkStateManager`) are modular and testable.
- Testability hooks: verbose mode, injectable pieces (partially), and state capture/restore enable safer tests and integration.

## Weaknesses (Library Use)

- Eager CLI load: `lib/wifi-wand.rb` requires `wifi-wand/main`, which pulls in CLI (`command_line_interface`), `optparse`, and `awesome_print`. This couples library usage to CLI deps and increases load time/memory.
- Runtime dependencies not ideal for libraries: `pry`, `awesome_print`, `reline`, `ostruct` are declared as runtime deps; consumers pay the cost even without CLI/interactive usage.
- Circular require smell: `command_line_interface.rb` requires `require 'wifi-wand'` (the entrypoint) while being loaded by that entrypoint.
- Output side effects: various classes use `puts`/`$stderr` when verbose; only `NetworkConnectivityTester` offers IO injection. A library should prefer an injected logger/IO throughout.
- External command assumptions: `BaseModel#public_ip_address_info` shells to `curl` without timeouts, adding an unnecessary runtime requirement and potential blocking.
- Ubuntu detection breadth: Ubuntu detector falls back to a general Linux match; non‑Ubuntu distros may be misidentified, surprising library users.

## Current Test Coverage (Library View)

- Strong unit coverage across errors, OS detection, models (macOS/Ubuntu), services, and CLI.
- Entry point tests for `WifiWand.create_model` exist.
- Gaps for library embedding concerns: no explicit tests for require‑time side effects, limited contract tests over the public model API surface, and no checks that library usage avoids CLI dependencies.

## Recommended Library‑Focused Tests

- Require behavior
  - Requiring `wifi-wand` does not mutate `ARGV`, start the shell, or print anything.
  - If CLI remains eager‑loaded, at least assert no code executes on require.
- Public API contract
  - For `WifiWand.create_model(options)`, assert returned models respond to the documented public methods (`wifi_info`, `wifi_on?`, `connect`, `disconnect`, `nameservers`, `set_nameservers`, `till`, `generate_qr_code`).
  - Verify options handling (`verbose`, `wifi_interface`) and error raising (`InvalidInterfaceError`, `InvalidNetworkNameError`).
- Output discipline
  - With `verbose: false`, no output is emitted; with `verbose: true`, output goes to an injected IO/logger where applicable.
- Resilience/permissions
  - Stub OS commands to simulate missing tools and permission failures; assert `CommandNotFoundError`, `WifiEnableError`, `WifiDisableError` as appropriate.
- Concurrency/resource safety
  - `NetworkConnectivityTester` threads are cleaned up; timeouts are respected under `RSPEC_RUNNING`.
- OS detection boundaries
  - Ensure non‑Ubuntu Linux is not incorrectly classified as Ubuntu (or document/guard this behavior).

## Suggested Refactors (Improve Library Use)

- Decouple CLI from default require
  - Make `lib/wifi-wand.rb` load only library files. Move CLI behind `require 'wifi-wand/cli'` or keep it solely under `exe/`.
  - Remove `require 'wifi-wand'` from `command_line_interface.rb`; require specific files to avoid circularity.
- Adjust gemspec
  - Move `pry`, `awesome_print`, and `reline` to development or CLI‑only scope; keep runtime deps minimal for library consumers.
- IO/logging hygiene
  - Replace ad‑hoc `puts` with an injected logger or IO (default no‑op) across all verbose output paths.
- Networking
  - Replace `curl` usage in `public_ip_address_info` with `Net::HTTP` and explicit timeouts.
- OS detection
  - Tighten Ubuntu detection or explicitly document that “generic Linux” maps to the Ubuntu (NetworkManager) implementation; consider naming it accordingly.

## Bottom Line

The core library structure is solid: a coherent API, modular services, and good error handling. To be a first‑class embedded library, decouple the CLI from the default require, slim runtime dependencies, add a few library‑integration tests focused on require‑time safety and API contracts, and standardize output/logging. These changes reduce friction for application integrators without altering core behavior.

