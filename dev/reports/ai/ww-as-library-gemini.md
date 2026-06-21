# Analysis of `wifiwand` as a Library

This document contains an analysis of the `wifiwand` codebase for its potential use as a Ruby library in
other applications.

## Strengths

1. **Modular and Well-Structured Core Logic:** The logic is cleanly separated into namespaces like `Services`,
   `OS`, and `Models`. This is a significant strength. A developer could theoretically pick and choose
   necessary components, for example, using just the `NetworkConnectivityTester` or the `ConnectionManager`.
2. **Clear OS Abstraction:** The separation of `MacOS` and `Ubuntu` logic (in both `lib/wifi_wand/os` and
   `lib/wifi_wand/models`) is excellent. This makes the core logic adaptable and extensible for other
   operating systems without requiring major refactoring.
3. **Comprehensive Test Coverage:** The `spec/` directory is extensive and appears to mirror the `lib/`
   directory structure very well. This indicates a high degree of existing test coverage, which provides a
   strong safety net for any refactoring and inspires confidence in the reliability of the core components.
4. **Centralized Error Handling:** The `errors.rb` file suggests a dedicated system for handling exceptions,
   which is crucial for a library that needs to communicate problems back to the consuming application.

## Weaknesses

1. **CLI-Centric Architecture:** The primary weakness is that the entire project is architected as a
   command-line application. The `main.rb` file and the entire `command_line_interface` directory are geared
   towards parsing arguments and printing to the console. A library should not have these concerns.
2. **No Clear Public API:** There doesn't appear to be a single, clean entry point for a library consumer. For
   example, there is no top-level class or module designed for programmatic use. A developer would have to
   read the source and manually instantiate classes from the `Services` or `Models` namespaces, which is not
   ideal.
3. **Potential for Side Effects:** Code designed for a CLI often contains side effects like `puts` for output,
   `gets` for input, or `exit` calls. These are highly undesirable in a library context, as they interfere
   with the host application's control flow and I/O.

## Recommendations for Test Coverage

It is recommended to **add a new layer of test coverage** specifically for the library use case.

While the existing unit tests for the services and models are invaluable, they likely test the components in
isolation. A new test suite should be created to validate the code *from the perspective of a library
consumer*.

This new suite would:
1.  `require 'wifi_wand'` as a library.
2.  Instantiate the public-facing classes you decide to expose.
3.  Call methods and assert their *return values*, not their console output.
4.  Ensure that no unexpected output is printed to STDOUT/STDERR during normal operation.
5.  Verify that custom errors are raised correctly instead of the program exiting.

This test suite would not only validate the library's functionality but also serve as living documentation for
how to use it.

## Proposed Next Steps

To confirm this analysis and plan a path forward, the following files should be inspected to understand the
current level of coupling between the core logic and the CLI:

1.  `lib/wifi_wand.rb`: To see what is loaded and exposed by default.
2. `lib/wifi_wand/main.rb`: To understand how the CLI application is initiated and how it uses the core
   services.
3. `lib/wifi_wand/services/connection_manager.rb`: To examine a core service and see if it has any direct
   dependencies on the CLI (like printing output).
---

## Revised Findings (Post-Analysis)

Historical note: this section originally recommended introducing a facade
object for library callers and decoupling the library entry point from the CLI.
The codebase has since moved in a different direction on the facade question,
but the CLI decoupling is complete. The public library entry point is now
`WifiWand.create_model`, which returns a concrete OS-specific model directly.

My analysis after reading the key files confirms the initial assessment and clarifies the path to refactoring
`wifiwand` into a proper library.

* **`lib/wifi_wand/services/connection_manager.rb` is a perfect library component.** It has zero dependencies
  on the command-line interface. It accepts objects, calls methods on them, and raises specific, catchable
  `WifiWand::Error` exceptions on failure. This is exactly what you want in a library.

* **`lib/wifi_wand/main.rb` is purely for the CLI.** It's responsible for parsing command-line options
  (`OptionParser`), handling `ARGV`, and printing formatted output and errors to `$stdout`. This file is the
  primary source of the tight coupling.

* **`lib/wifi_wand.rb` is now the library entry point.** It loads the core library components without loading
  the CLI application, and exposes `WifiWand.create_model` as the public entry point.

## The Path Forward: Decoupling

The goal is to make it so that `require 'wifi_wand'` provides access to the core logic *without* loading any
of the command-line interface code. The CLI code should only be loaded when the `exe/wifiwand` executable is
run.

This plan has been implemented:

1. **Isolate the CLI Entrypoint:** The main executable `exe/wifiwand` explicitly requires `wifi_wand/main`,
   making it the sole entry point for the command-line application.

2. **Decouple the Library:** `lib/wifi_wand.rb` requires the individual components that form the library's
   core, such as the services, models, and errors.

3. **Establish a Clear Public API:** The current codebase now does this with
   `WifiWand.create_model` and the concrete model classes rather than with a
   separate facade object. That keeps OS detection and model behavior explicit
   without adding another wrapper layer.
