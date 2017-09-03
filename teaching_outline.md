# Outline for Code Tour of mac-wifi

What would you possibly use Ruby for other than Rails?

1) Use of external commands
    * the `run_command` method
    * illustrate use outside this program
1) in `wifi_hardware_port`
    * use of `||=`
    * use of comment illustrating output to be parsed 
    * use of `detect`
    * use of `%Q`
    * use of `split`
1) in `preferred_networks`
    * using `!` methods on an array
    * case insensitive sort using `casecmp`
1) in `cycle_network`
    * saving and restoring network -- be nice to the user
    * all code is high level, no low level details
1) in `connect`
    * use of precondition
    * use of Shellwords.shellescape, illustrate w: ``F=`./mac-wifi lsp | grep ' ' | head -1` ``
1) in `ip_address`
    * the need for chomp when processing standard output
1) in `remove_preferred_network`
    * don't try deleting if nonexistent; eliminates need for sudo authentication
    * use of `*` - show how specification differs batch vs. interactive
    * use of `reject`
    * use of `any?`
    * point out that this is a precondition, but for return, not error
    * be nice to your user; warn them about the bare "Password:" prompt
    * use `raise` instead of `exit`; you can't predict how your code will be used (shell was added later)
    