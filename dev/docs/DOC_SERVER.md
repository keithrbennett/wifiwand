# Documentation Server

This project uses MkDocs to serve the Markdown documentation locally. The repository keeps the Python
documentation dependencies separate from the Ruby gem dependencies in `.docs-venv`.

The helper scripts resolve repository paths themselves, so you can invoke them from any working directory.
The docs dependency set requires Python 3.10 or newer.

## First-Time Setup

Use the setup script when you want the fastest interactive setup:

```bash
source /path/to/wifiwand/bin/set-up-python-for-doc-server
```

The script must be sourced because it creates and activates `.docs-venv` in the current shell. It installs the
locked Python packages from `requirements-lock.txt`, including MkDocs and the configured MkDocs plugins.
If your default `python3` is older than 3.10, make `python3` resolve to a newer interpreter before sourcing
the script.

After setup, start the server:

```bash
/path/to/wifiwand/bin/start-doc-server
```

MkDocs prints the local URL when it starts. By default, the site is served at:

```text
http://127.0.0.1:8000/
```

The server watches the generated Markdown workspace under `tmp/` and reloads the browser after changes. Stop
it with `Ctrl+C`. Because the helper scripts copy repository files into that generated workspace at startup,
restart the server after changing `mkdocs.yml`, `README.md`, or files outside the generated `tmp/` tree.

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

## Dependency Updates and Audits

The documentation tooling is pinned in `requirements-lock.txt`, so it does not pick up security fixes on its
own. Two scripts (each also available as a Rake task) keep it current. Both create a temporary virtual
environment outside the repository, remove it when they finish, and need network access to PyPI:

```bash
bin/audit-docs-deps    # or: rake docs:audit
bin/update-docs-deps   # or: rake docs:update_deps
```

- `bin/audit-docs-deps` checks `requirements-lock.txt` with `pip-audit` and exits non-zero if it finds known
  vulnerabilities.
- `bin/update-docs-deps` reinstalls from the version ranges in `requirements.txt` and rewrites
  `requirements-lock.txt` only if every step succeeds. Afterward, review `git diff requirements-lock.txt`, run
  `bin/build-docs`, and re-run the audit. If an advisory needs a version outside a range in
  `requirements.txt`, widen the range first.

`rake security` runs this audit together with the Ruby audits.

CI runs `bin/audit-docs-deps` in the **Security audit** job, so a newly published advisory against a pinned
package fails that job until `requirements-lock.txt` is updated.

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

## Publishing Documentation

The GitHub Actions workflow publishes a GitHub Pages artifact only for final release tags matching `vX.Y.Z`
(for example `v3.0.1`). Pre-release tags such as `v3.1.0.pre1` or `v3.1.0-rc1` do not publish documentation.
Pull requests and documentation-related pushes to `main` only build the site for validation. The web
documentation is refreshed when the next final release tag is published.

To republish a released version, open the **Docs** workflow in GitHub Actions, choose **Run workflow**, and
select that version tag. A manual run on a pre-release tag fails at the workflow's release-tag check. GitHub
runs the workflow file as it exists at the selected tag, so tags that predate this workflow (such as `v3.0.0`)
cannot be republished this way.

Repository settings required for publishing:

- GitHub Pages must be configured to deploy from **GitHub Actions**.
- The `github-pages` environment must allow deployments from `v*` tags (**Settings > Environments >
  github-pages > Deployment branches and tags**). Otherwise, tag deploys are rejected with "not allowed to
  deploy to github-pages due to environment protection rules".

## Key Files

- `mkdocs.yml` - MkDocs configuration, plugin setup, excluded paths, and site navigation.
- `docs/index.md` - MkDocs landing page; it includes the project `README.md`.
- `requirements-lock.txt` - Locked Python dependencies used by the setup script and Rake task.
- `requirements.txt` - Broad dependency constraints for documentation tooling.
- `bin/set-up-python-for-doc-server` - First-time interactive environment setup.
- `bin/start-doc-server` - Starts `mkdocs serve` with the project configuration.
- `bin/build-docs` - Runs `mkdocs build --strict` with the project configuration.
- `bin/audit-docs-deps` - Audits `requirements-lock.txt` for known vulnerabilities with `pip-audit`.
- `bin/update-docs-deps` - Regenerates `requirements-lock.txt` from `requirements.txt`.

## Troubleshooting

If `bin/start-doc-server` reports that `mkdocs` is missing, run:

```bash
source /path/to/wifiwand/bin/set-up-python-for-doc-server
```

If `python3 -m venv` is unavailable on Ubuntu, install the system venv package for your Python version and run
the setup command again.

If setup fails while installing packages with errors about unsupported Python versions or missing matching
distributions, your `python3` is probably older than 3.10. Install Python 3.10 or newer, make sure `python3`
resolves to it, and run the setup command again.

If port `8000` is already in use, pass another address through the helper script:

```bash
/path/to/wifiwand/bin/start-doc-server --dev-addr 127.0.0.1:8001
```

If rendered Markdown still looks stale after restarting the server, hard-refresh the browser page. For
example, use `Cmd+Shift+R` on macOS.
