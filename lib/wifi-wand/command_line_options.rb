# frozen_string_literal: true

module WifiWand
  CommandLineOptions = Struct.new(
    :verbose,
    :post_processor,
    :wifi_interface,
    :version_requested,
    :help_requested,
    :argv,
    :interactive_mode,
    :out_stream,
    :err_stream,
    :in_stream,
    keyword_init: true
  )
end
