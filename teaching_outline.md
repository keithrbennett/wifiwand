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
1) in `current_network`
    * blind use of `first` when expecting only 1 result
1) in `awesome_print_available?`
    * although the name implies query only, it also has `require` side effect
    * `require` will load a given gem only once (unlike `load`)
    * must rescue `LoadError`, else error will not be rescued
1) in `validate_command_line`
    * use of `empty?`, `any?` in arrays
    * be sure to use a nonzero exit code for error exits
1) in `run_os_command`
    * this method's purpose of existence: common needs w/running external commands
    * merging stderr with stdout using `2>&1`
    * useful return value - don't forget to return the output when successful!
1) in `run_shell`
    * precondition: prevent more than 1 shell invocation (though pry can do multiple prys)
    * limiting calls to `require` by putting them only in code that needs it
    * providing better error messages than raw error output
1) in `method_missing`
    * used solely by interactive mode
    * can use this because pry evaluates calls in the context of the current object
1) in `process_command_line`
    * use of `quit` lambda as a nested function to eliminate code duplication w/o cluttering method list
    * using regexes with `case`
1) in `call`
    * formalizes entry point into the class in a way that is semantically consistent w/other callables such as lambdas
1) `MacWifi.new.call`
    * program entry point
    * only code other than `require` outside of the class  
    