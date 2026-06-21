# frozen_string_literal: true

module WifiWand
  CommandLineOptions = Struct.new(
    :verbose,
    :utc,
    :post_processor,
    :output_format,
    :wifi_interface,
    :version_requested,
    :help_requested,
    :command_options,
    :specified_invocation_options,
    :invocation_option_sources,
    :argv,
    :raw_argv,
    :wifi_wand_opts_env,
    :interactive_mode,
    :out_stream,
    :err_stream,
    :in_stream,
    keyword_init: true
  )
end
