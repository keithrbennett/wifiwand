# Developer Documentation Index

This directory is for `wifi-wand` maintainers and developers. These documents contain deep technical details,
research, and internal strategy.

## macOS Helper Development

- **[macOS Helper Research](MAC_HELPER_RESEARCH.md)** - Original research into why and how the native macOS
  helper was implemented.
- **[macOS Helper Permissions](MAC_HELPER_PERMISSIONS.md)** - Documentation of the helper's permission
  behavior and the "com.wifiwand.helper" bundle identity.
- **[macOS Code Signing (Context)](MACOS_CODE_SIGNING_CONTEXT.md)** - Technical context for macOS code signing
  and notarization.
- **[macOS Code Signing (Instructions)](MACOS_CODE_SIGNING_INSTRUCTIONS.md)** - Step-by-step instructions for
  maintainers to sign and notarize a release.

## Developer Environment

- **[Isolated AI Dev VM Setup](AI_VM_SETUP.md)** - Step-by-step guide for building an isolated VM-based
  development environment with Ansible, suitable for Linux now and Apple Silicon later.
- **[Reviewed Agent Issues](REVIEWED_AGENT_ISSUES.md)** - Previously reviewed objections that agents/reviewers
  should not re-raise without new evidence.

## General Information

- **[Command Architecture](COMMAND_ARCHITECTURE.md)** - Detailed explanation of the current command scheme,
  including command binding, registry dispatch, shell integration, and the `CommandOutputSupport` boundary.
- **[`connected?` vs `internet_connectivity_state`](CONNECTED_VS_INTERNET_CONNECTIVITY.md)** - Analysis of
  the semantic split between WiFi connection state and host-level internet reachability, with API cleanup
  suggestions.
- End-user documentation should be prioritized by contributors in the **[Main Documentation
  Index](../README.md)**.
- For internal testing strategies and CI details, refer to the **[Testing Guide](../TESTING.md)**.
