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
* Improved handling of attempting to list available networks when wifi is off.


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



