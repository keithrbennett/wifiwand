## v3.0.0

**BREAKING CHANGES:**
* 'Connected to Internet' now ignores WiFi on/off since there can be an Ethernet connection to the Internet.
* `cycle_network` now toggles WiFi state twice for both starting states (on and off)

* **Architecture overhaul** - Complete restructure with OS abstraction layer for cross-platform compatibility
* **Remove legacy macOS-specific features** - Removed Speedtest app launcher, fancy_print dependency, and macOS-specific code paths
* **Error handling improvements** - Added comprehensive error classes and improved error messaging
* **Testing framework redesign** - Implemented OS-specific test filtering and disruptive/non-disruptive test categorization

**New Features:**
* **Add Ubuntu/Linux support** - WiFi-wand now supports Ubuntu and compatible Linux distributions in addition to macOS
* **Cross-platform WiFi management** - Unified API supporting both macOS and Ubuntu/Linux systems  
* **Ubuntu support via NetworkManager** - Full Ubuntu WiFi operations using `nmcli`, `iw`, and `ip` commands
* **Interactive shell improvements** - Enhanced Pry-based shell with better help system and output formatting
* **Environment variable control** - Added `WIFIWAND_VERBOSE` and `RSPEC_DISABLE_EXCLUSIONS` for better control
* **Resource management system** - Automated network state capture/restore for testing
* **Connection management** - Intelligent password saving and network reconnection logic

**Improvements:**
* **Modular architecture** - Extracted functionality into specialized modules (HelpSystem, OutputFormatter, ErrorHandling, etc.)
* **Enhanced output formatting** - Improved JSON/YAML output with proper formatting for different output targets  
* **Better error messages** - Cleaner error output without backtraces except in verbose mode
* **Robust OS detection** - Improved operating system detection and model instantiation
* **Test suite enhancements** - Comprehensive test coverage with OS-aware test filtering
* **Documentation updates** - Updated README and documentation to reflect Ubuntu support

**Bug Fixes:**
* **Ubuntu connection stability** - Fixed unnecessary reconnections and improved error handling for Ubuntu
* **Output formatting fixes** - Fixed `-op` output with StringIO requirement for modern Ruby versions
* **Test exclusions** - Fixed macOS disruptive tests exclusion when running on Ubuntu
* **Ruby compatibility** - Added StringIO require and Reline dependency for Ruby >= 3.5.0
* **Command execution** - Improved shell command escaping and argument handling

**Technical Changes:**
* **Dependency updates** - Updated gemspec with proper Ruby version requirements and dependencies
* **Code organization** - Moved to layered architecture with clear separation of concerns  
* **YAML configuration** - Extracted hardcoded data into YAML configuration files
* **Status monitoring** - Enhanced connection status monitoring with configurable timeouts
* **Mock testing** - Removed real OS commands from non-disruptive unit tests

This major release represents a complete rewrite focused on cross-platform support while maintaining backward compatibility for existing macOS users.

* Added 's/status' status line command.


## v2.20.0

* Change detect_wifi_interface and available_network_names to use system_profiler JSON output.
* Previously, detect_wifi_interface parsed human readable text; parsing JSON is more reliable.
* Previously, available_network_names used Swift and CoreLAN and required XCode installation.


## v2.19.1

* Fix connected_network_name when WiFi is on but no network is connected.


## v2.19.0

* Replace `networksetup` with Swift script for connecting to a network.
* For getting connected network name, replace `networksetup` with `ipconfig`. 


## v2.18.0

* Remove 'hotspot_login_required' informational item and logic (was not working correctly).


## v2.17.1

* Fix verbose output for running a Swift command. 
* Exit Swift programs with code 1 on error.
* Remove rexml dependency, no longer needed.


## v2.17.0

* Remove all remaining uses of the 'airport' command.
* Remove 'available_network_info' command which required the 'airport' command.
* Remove extended information in the 'info' command output, which required the 'airport' command.
* Remove unused ModelValidator class.
* In README, update license reference and make other edits.


## v2.16.1

* Fix airport deprecations' removal of listing all networks and disconnecting from a network by using Swift scripts.


## v2.16.0 (2024-04)

* Handle deprecation of the `airport` command starting at macOS 14.4.
* Add hotspot_login_required functionality.
* Change 'port' to 'interface' in some names.
* Add to external resources: captive.apple.com, librespeed.org
* Change license from MIT to Apache 2.


## v2.15.2

* Improve support for 'hotspot login required'.
* Add 'hotspot_login_required' field to info hash, & on connect, opens captive.aple.com page if needed.
* Change license from MIT to Apache 2.


## v2.15.1

* Fix bug; when calling connect with an SSID with leading spaces, a warning was erroneously issued about the SSID.


## v2.15.0

* Allow using symbols in the 'nameservers' subcommands.
* Modify `forget` method to allow passing a single array of names, as returned by `pr.grep`, for example.
* Output duration of http get's.


## v2.14.0

* `ls_avail_nets` command now outputs access points in signal strength order.
* Add logo to project, show it in README.md.

## v2.13.0

* Fix: network names could not be displayed when one contained a nonstandard character (e.g. D5 for a special apostrophe in Mac Roman encoding).
* Fix: some operations that didn't make sense with WiFi off were attempted anyway; this was removed.

## v2.12.0

* Change connected_to_internet?. Use 'dig' to test name resolution first, then HTTP get. Also, add baidu.com for China where google.com is blocked.
* Remove ping test from connected_to_internet?. It was failing on a network that had connectivity (Syma in France).
* Remove trailing newline from MAC address.
* Fix nameservers command to return empty array instead of ["There aren't any DNS Servers set on Wi-Fi."] (output of underlying command)when no nameservers.


## v2.11.0

* Various fixes and clarifications.
* Change implementation of available_network_names to use REXML; first implemented w/position number, then XPath.
* Add attempt count to try_os_command_until in verbose mode.

## v2.10.1

* Fix egregious bug; the 'a' command did not work if `airport` was not in the path; I should have been using the AIRPORT_CMD constant but hard coded `airport` instead.

## v2.10.0

* Rename rm[_pref_nets] command to f[orget].
 

## v2.9.0

* Add duration of command to verbose output.
* Add MAC address to info hash.
* Reduce ping timeout to 3 seconds for faster return for `info`, `ci` commands.
* Replace ipchicken.com link with iplocation.net link for 'ropen'; iplocation aggregates several info sources.
* Fix bug where if there were no duplicate network names, result was nil, because uniq! returns nil if no changes!!!
* Suppress error throw on ping error when not connected; it was printing useless output.

## v2.8.0

* Substantial simplifications of model implementations of connected_to_internet?, available_network_names.
* Fixed network name reporting problems regarding leading/trailing spaces.
* Improve verbose output by printing command when issued, not after completed.


## v2.7.0

* Fix models not being loadable after requiring the gem.
* Add message suggesting to gem install awesome_print to help text if not installed.
* Add Github project page URL to help text.
* Rename 'wifion' to 'wifi_on'.
* Change order of verbose output and error raising in run_os_commmand.


## v2.6.0

* Add support for getting and setting DNS nameservers with 'na'/'nameservers' command.
* Improve error output readability for top level error catching.


## v2.5.0

* Add limited support for nonstandard WiFi devices (https://github.com/keithrbennett/wifiwand/issues/6).


## v2.4.2

* Fix test.


## v2.4.1

* Fix bug: undefined local variable or method `connected_network_name'.


## v2.4.0

* Project has been renamed from 'mac-wifi' to 'wifi-wand'.
* Further preparation for addition of support of other OS's.
* Make resource opening OS-dependent as it should be.
* Move models to models directory.
* Refactored OS determination and model creation.
* Use scutil --dns to get nameserver info, using the union of the scoped and unscoped nameservers.


## v2.3.0

* Add public IP address info to info hash (https://github.com/keithrbennett/macwifi/issues/3).
* Add nameserver information to info hash (issue at https://github.com/keithrbennett/macwifi/issues/5).
* Made all info hash keys same data type to be less confusing; made them all String's.
* Replace 'public-ip-show' with 'ropen', and provide additional targets ipchicken.com,
 speedtest.net, and the Github page for this project
* Speed up retrieval of network name
* Remove BaseModel#run_os_command private restriction.


## v2.2.0

* Add pu[blic-wifi-show] command to open https://www.whatismyip.com/ to show public IP address info.
* Removed 'vpn on' info from info hash; it was often inaccurate.


## v2.1.0

* Support for the single script file install has been dropped. It was requiring too much complexity,
and was problematic with Ruby implementations lacking GEM_HOME / GEM_PATH environment variables.
* Code was broken out of the single script file into class files, plus a `version.rb`
and `mac-wifi.rb` file.


## v2.0.0

* Support output formats in batch mode: JSON, YAML, puts, and inspect modes.
* Change some command names to include underscores.
* Shell mode is now (only) a command line switch (-s).


## v1.4.0

* Support for "MAC-WIFI-OPTS" environment variable for configuration dropped.
* Support for "-v" verbosity command line option added.
* Work around pry bug whereby shell was not always starting when requested.
* 99% fix for reporting of available network names containing leading spaces
  (this will not correctly handle the case of network names that are identical
  except for numbers of leading spaces).
* Improved handling of attempting to list available networks when WiFi is off.


## v1.3.0

* Add partial JSON and YAML support.
* Script moved from bin to exe directory.
* Provide `fp` fancy print alias for convenience in shell.
* Command renames: 'lsp' -> 'prefnets', 'rm' -> 'rmprefnets'
* Add 'availnets' command for list of unique available network names.


## v1.2.0

* Fix: protect against using command strings shorter than minimum length
      (e.g. 'c', when more chars are necessary to disambiguate multiple commands).
* Improvements in help text and readme.


## v1.1.0

* Sort available networks alphabetically, left justify ssid's.
* to_s is called on parameters so that symbols can be specified in interactive shell for easier typing


## v1.0.0

* First versioned release.



