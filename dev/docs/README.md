# Developer Documentation Index

This directory is for `wifi-wand` maintainers and developers. These documents contain deep technical details,
research, and internal strategy.

Use [../../docs/README.md](../../docs/README.md) for end-user and operator documentation.

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
- **[Testing Guide](TESTING.md)** - Test scopes, real-environment tags, coverage artifact handling, and CI
  expectations.

## Documentation Server

This repo can now serve its Markdown docs locally with MkDocs, using the same basic pattern as `cov-loupe`.

```bash
source bin/set-up-python-for-doc-server
bin/start-doc-server
```

The site will be available at `http://127.0.0.1:8000/` with live reload. For non-interactive use:

```bash
bundle exec rake docs:setup
bundle exec rake docs:build
```

Key files:

- `mkdocs.yml` - MkDocs configuration and navigation.
- `docs/index.md` - MkDocs landing page that includes the project `README.md`.
- `requirements.txt` / `requirements-lock.txt` - Python dependencies for docs work.
- `bin/start-doc-server` / `bin/build-docs` - Local serve and strict build helpers.

## General Information

- **[Command Architecture](COMMAND_ARCHITECTURE.md)** - Detailed explanation of the current command scheme,
  including command binding, registry dispatch, shell integration, and the `CommandOutputSupport` boundary.
- **[`public_ip` Command Architecture](PUBLIC_IP_COMMAND_DESIGN.md)** - Design notes for the dedicated
  external-IP command and its separation from `info`.
- **[`connected?` vs `internet_connectivity_state`](CONNECTED_VS_INTERNET_CONNECTIVITY.md)** - Analysis of
  the semantic split between WiFi connection state and host-level internet reachability, with API cleanup
  suggestions.

## Internal Reports And Planning

- **[AI Library Analysis: Claude](../reports/ai/ww-as-library-claude.md)** - One-off analysis of `wifi-wand`
  as a Ruby library.
- **[AI Library Analysis: Gemini](../reports/ai/ww-as-library-gemini.md)** - Alternate analysis of
  `wifi-wand` as a Ruby library.
- **[Naming Strategy Change Planning](wifiwand_naming_strategy-change-planning.md)** - Planning note for a
  possible `wifiwand` naming cleanup.

## Agent Prompts And Review Notes

- **[Prompt Library](../prompts/)** - Reusable prompts and reviewer guidance for internal workflows.
