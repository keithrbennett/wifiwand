# frozen_string_literal: true

module WifiWand
  class RuntimeConfig
    attr_reader :verbose, :utc
    attr_accessor :out_stream, :err_stream

    def initialize(verbose: false, utc: false, out_stream: $stdout, err_stream: $stderr)
      @verbose = !!verbose
      @utc = !!utc
      @out_stream = out_stream
      @err_stream = err_stream
    end

    def verbose=(value)
      @verbose = !!value
    end

    def utc=(value)
      @utc = !!value
    end

    def to_h
      {
        verbose:    verbose,
        utc:        utc,
        out_stream: out_stream,
        err_stream: err_stream,
      }
    end
  end
end
