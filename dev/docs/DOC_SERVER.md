# Documentation Server

This project uses MkDocs to serve the Markdown documentation locally. The repository keeps the Python
documentation dependencies separate from the Ruby gem dependencies in `.docs-venv`.

The helper scripts resolve repository paths themselves, so you can invoke them from any working directory.

## First-Time Setup

Use the setup script when you want the fastest interactive setup:

```bash
source /path/to/wifiwand/bin/set-up-python-for-doc-server
```

The script must be sourced because it creates and activates `.docs-venv` in the current shell. It installs the
locked Python packages from `requirements-lock.txt`, including MkDocs and the configured MkDocs plugins.

After setup, start the server:

```bash
/path/to/wifiwand/bin/start-doc-server
```

MkDocs prints the local URL when it starts. By default, the site is served at:

```text
http://127.0.0.1:8000/
```

The server watches Markdown and configuration files and reloads the browser after changes. Stop it with
`Ctrl+C`.

## Later Sessions

If `.docs-venv` already exists, activate it and start the server:

```bash
source /path/to/wifiwand/.docs-venv/bin/activate
/path/to/wifiwand/bin/start-doc-server
```

`bin/start-doc-server` also checks `.docs-venv/bin/mkdocs` first, so it can usually find the project-local
MkDocs executable even if the virtual environment is not currently active.

Extra MkDocs flags can be passed through the helper script. For example:

```bash
/path/to/wifiwand/bin/start-doc-server --dev-addr 127.0.0.1:8001
```

## Rake Tasks

The same workflow is available through Rake:

```bash
BUNDLE_GEMFILE=/path/to/wifiwand/Gemfile \
  bundle exec rake -f /path/to/wifiwand/Rakefile docs:setup
BUNDLE_GEMFILE=/path/to/wifiwand/Gemfile \
  bundle exec rake -f /path/to/wifiwand/Rakefile docs:serve
```

Use the Rake tasks for non-interactive setup or when you want to stay within the Ruby project tooling. The
`docs:setup` task creates `.docs-venv` and installs `requirements-lock.txt`.

## Strict Build Check

Before publishing or after changing MkDocs navigation, run a strict build:

```bash
/path/to/wifiwand/bin/build-docs
```

or:

```bash
BUNDLE_GEMFILE=/path/to/wifiwand/Gemfile \
  bundle exec rake -f /path/to/wifiwand/Rakefile docs:build
```

This builds with a temporary generated config, source tree, and site directory under `tmp/`, then removes
them when MkDocs exits. The command still fails on strict MkDocs errors. Git ignores both `.docs-venv/` and
`tmp/`. The committed MkDocs config still names `site/` as its default output directory, but the helper
scripts no longer leave a built site there.

## Key Files

- `mkdocs.yml` - MkDocs configuration, plugin setup, excluded paths, and site navigation.
- `docs/index.md` - MkDocs landing page; it includes the project `README.md`.
- `requirements-lock.txt` - Locked Python dependencies used by the setup script and Rake task.
- `requirements.txt` - Broad dependency constraints for documentation tooling.
- `bin/set-up-python-for-doc-server` - First-time interactive environment setup.
- `bin/start-doc-server` - Starts `mkdocs serve` with the project configuration.
- `bin/build-docs` - Runs `mkdocs build --strict` with the project configuration.

## Troubleshooting

If `bin/start-doc-server` reports that `mkdocs` is missing, run:

```bash
source /path/to/wifiwand/bin/set-up-python-for-doc-server
```

If `python3 -m venv` is unavailable on Ubuntu, install the system venv package for your Python version and run
the setup command again.

If port `8000` is already in use, pass another address through the helper script:

```bash
/path/to/wifiwand/bin/start-doc-server --dev-addr 127.0.0.1:8001
```
