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



