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



