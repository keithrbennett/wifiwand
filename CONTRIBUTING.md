# Contributing to WifiWand

[Back to the main README](README.md)

Thank you for your interest in contributing.

Bug reports, feature proposals, documentation suggestions, and other feedback are welcome.

---

## Before Submitting a Pull Request

Please do not submit a pull request unless you have first opened an issue and received explicit approval from the maintainer to proceed.

Discussing a proposal in an issue does not by itself constitute approval. Please wait until the maintainer specifically confirms that a pull request would be welcome.

This project is maintained by a single developer. Even a well-intentioned and technically sound pull request can require substantial review, testing, discussion, and ongoing maintenance. A proposed change may also conflict with the project's scope, design, priorities, or planned work.

The contribution process is:

1. Open an issue describing the problem or proposed improvement.
2. Discuss the desired behavior and, when useful, the likely implementation.
3. Wait for explicit approval to prepare a pull request.
4. Submit a pull request only after receiving that approval.

Pull requests submitted without prior approval may be closed without detailed review.

### AI-Assisted Contributions

AI-assisted work is welcomed. The same prior-approval requirement applies whether the work is produced manually or with AI assistance.

Contributors are responsible for supervising and validating their work. A pull request should not shift the primary burden of reviewing, debugging, or establishing correctness to the maintainer.

---

## Reporting Issues

Before opening an issue:

- Check whether an existing issue already addresses the subject.
- Include clear reproduction steps when reporting a problem.
- Describe the expected and actual behavior.
- Include your Ruby version (`ruby -v`), operating system, and relevant operating-system version.
- Identify whether the problem occurs on macOS or Ubuntu.
- Include relevant WifiWand command output, while removing passwords and other sensitive information.
- Include any other environment information relevant to reproducing the problem.

WifiWand invokes operating-system networking tools and can interact with WiFi credentials and local network configuration. Review the [Security Notes](docs/SECURITY_NOTES.md) before posting diagnostic output.

---

## Preparing an Approved Change

After receiving explicit approval to submit a pull request:

1. Fork the repository on GitHub.
2. Clone your fork and enter the project directory:

   ```bash
   git clone https://github.com/YOUR-USERNAME/wifiwand.git
   cd wifiwand
   ```

3. Create a branch for your work:

   ```bash
   git checkout -b feature/my-change
   ```

4. Install dependencies:

   ```bash
   bundle install
   ```

5. Make your changes, following the project's existing coding style.
6. Test and validate the changes as described below.
7. Commit the changes with a clear, informative message.
8. Push the branch and open a pull request against `main`.

Pull requests should:

- Link to the issue in which the change was approved.
- Include or update tests for new or changed behavior.
- Pass the applicable test suites and RuboCop checks.
- Update documentation and examples when behavior changes.
- Explain how the change was tested and validated.
- Identify the operating systems and versions on which the change was tested when platform-specific behavior is involved.
- Clearly distinguish mocked testing from testing performed against a real host environment.

---

## Testing Approved Changes

Run the default test suite and RuboCop before submitting a pull request:

```bash
bundle exec rspec
bundle exec rubocop
```

For changes affecting operating-system-specific networking behavior, also run the full real-environment test suite on the affected platforms:

```bash
bundle exec rake test:all
```

Real-environment tests depend on the host's WiFi hardware, operating-system state, permissions, and saved network configuration. Some tests may temporarily modify network state and use capture-and-restoration safeguards.

Before running them, review the [Testing Guide](dev/docs/TESTING.md).

In the pull request, identify:

- The operating systems and versions tested.
- Whether testing included the default suite, real-environment tests, or both.
- Any relevant behavior that could not be tested.
