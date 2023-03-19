require_relative 'wifi-wand/version'

require_relative 'wifi-wand/main'  # recursively requires the other files
#
# When additional operating systems are added, we will need to modify this
# to load only the model appropriate for the environment:

require_relative 'wifi-wand/models/mac_os_model'
