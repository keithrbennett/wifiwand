# frozen_string_literal: true

require 'json'

require_relative '../../errors'

module WifiWand
  module Platforms
    module Mac
      class AirportDataProvider
        CACHE_CONTEXTS_KEY = :wifi_wand_airport_data_cache_contexts
        SYSTEM_PROFILER_AIRPORT_ARGS = %w[system_profiler -json SPAirPortDataType].freeze
        SYSTEM_PROFILER_TIMEOUT_SECONDS = 15

        def initialize(owner:, command_runner:)
          @owner = owner
          @command_runner = command_runner
          @cache_mutex = Mutex.new
          @cache_generation = 0
        end

        def with_cache_scope
          context = enter_cache_scope
          yield
        ensure
          exit_cache_scope(context) if context
        end

        def data(timeout_in_secs: nil)
          context = active_cache_context
          generation = cache_generation
          return context[:data] if cached_data_current?(context, generation)

          parsed_data = parse_system_profiler_airport_data(timeout_in_secs: timeout_in_secs)

          cache_data(context, generation, parsed_data)
          parsed_data
        end

        def invalidate_cache
          @cache_mutex.synchronize do
            @cache_generation += 1
          end

          context = active_cache_context
          return unless context

          context.delete(:data)
          context.delete(:generation)
        end

        def active_cache_context
          current_cache_contexts&.fetch(@owner, nil)
        end

        private def enter_cache_scope
          context = active_cache_context

          if context
            context[:depth] += 1
          else
            context = { depth: 1 }
            cache_contexts[@owner] = context
          end

          context
        end

        private def exit_cache_scope(context)
          context[:depth] -= 1
          return if context[:depth].positive?

          contexts = current_cache_contexts
          contexts&.delete(@owner)
          Thread.current[CACHE_CONTEXTS_KEY] = nil if contexts&.empty?
        end

        private def current_cache_contexts
          Thread.current[CACHE_CONTEXTS_KEY]
        end

        private def cache_contexts
          Thread.current[CACHE_CONTEXTS_KEY] ||= {}.compare_by_identity
        end

        private def cache_generation
          @cache_mutex.synchronize { @cache_generation }
        end

        private def cached_data_current?(context, generation)
          context&.key?(:data) && context[:generation] == generation
        end

        private def cache_data(context, generation, parsed_data)
          return unless context
          return unless generation == cache_generation

          context[:data] = parsed_data
          context[:generation] = generation
        end

        private def parse_system_profiler_airport_data(timeout_in_secs: nil)
          json_text = @command_runner.call(
            SYSTEM_PROFILER_AIRPORT_ARGS,
            raise_on_error:  true,
            timeout_in_secs: timeout_in_secs || SYSTEM_PROFILER_TIMEOUT_SECONDS
          ).stdout
          JSON.parse(json_text)
        rescue JSON::ParserError => e
          raise SystemProfilerError, "Failed to parse system_profiler output: #{e.message}"
        end
      end
    end
  end
end
