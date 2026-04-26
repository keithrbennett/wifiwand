# frozen_string_literal: true

module WifiWand
  class RuntimeConfig
    attr_reader :verbose
    attr_accessor :out_stream

    def initialize(verbose: false, out_stream: $stdout)
      @verbose = !!verbose
      @out_stream = out_stream
    end

    def verbose=(value)
      @verbose = !!value
    end

    def to_h
      {
        verbose:    verbose,
        out_stream: out_stream,
      }
    end
  end
end
