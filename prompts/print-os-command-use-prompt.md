# Printing OS Command Use Information

Create or modify a markdown file with the information I will describe below.

### Naming the Output Markdown File

* If the filename is specified in this prompt:
  * Use it
* Else:
  * Build a default filespec using "docs/os-command-use-#{os_name}" and adding "-#{model_abbrev}" 
    if you know which model you are.
  * Prompt the user to ask for a filespec, offering the default, to which the user can reply '.' to use the default.
  * Use the reply as the filespec, where '.' is replaced by your default filespec

### OS Selection

* If the OS is specified in this prompt:
    * Use it
* Else:
  * Ask the user. Currently the choices are Ubuntu and macOS. Use their response.

### File Header

* Create the file and write to it (on the same line separated by ' -- ' if combined its length is <= 80 chars):
  * title
  * date/time generated, in UTC

----

* In that document, for each operating system commands it uses:
  * Print briefly any useful information that is not obvious (e.g. SSID's vs. network profiles in Network Manager)
  * For each form (that is, commands, subcommands, parameters), output:
    * base model method name(s) that use this command
    * command line interface commands that call any of those methods
    * 1 line description                                                                                                                           
    * dynamic values coming from ruby variables                                                                                                    
    * any other helpful detailed info, esp. re: Ubuntu network profiles                                                                            

More:

* You probably only need to look at the lib/**/*.rb files.
* If the file already exists, note and follow the existing format.
  As much as possible, we don't want to have git diffs that are not relevant to the content.
