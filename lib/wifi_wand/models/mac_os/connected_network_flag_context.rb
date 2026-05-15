# frozen_string_literal: true

module WifiWand
  # Tracks per-thread connected-network lookup flags without leaking state across nested calls.
  module MacOsConnectedNetworkFlagContext
    FLAG_CONTEXTS_KEY = :wifi_wand_mac_os_network_identity_flag_contexts

    private def with_connected_network_flag_scope
      contexts = connected_network_flag_contexts
      had_previous_context = contexts.key?(self)
      previous_context = contexts[self] if had_previous_context

      contexts[self] = new_connected_network_flag_context
      yield
    ensure
      restore_connected_network_flag_context(contexts, had_previous_context, previous_context)
    end

    private def mark_connected_network_authoritatively_disconnected
      active_connected_network_flag_context&.[]=(:authoritatively_disconnected, true)
      nil
    end

    private def connected_network_authoritatively_disconnected?
      context = active_connected_network_flag_context
      context ? context.fetch(:authoritatively_disconnected) : false
    end

    private def mark_connected_network_fallback_identity_redacted
      active_connected_network_flag_context&.[]=(:fallback_identity_redacted, true)
      nil
    end

    private def connected_network_fallback_identity_redacted?
      context = active_connected_network_flag_context
      context ? context.fetch(:fallback_identity_redacted) : false
    end

    private def new_connected_network_flag_context
      {
        authoritatively_disconnected: false,
        fallback_identity_redacted:   false,
      }
    end

    private def restore_connected_network_flag_context(contexts, had_previous_context, previous_context)
      if had_previous_context
        contexts[self] = previous_context
      else
        contexts.delete(self)
      end

      Thread.current[FLAG_CONTEXTS_KEY] = nil if contexts.empty?
    end

    private def active_connected_network_flag_context
      current_connected_network_flag_contexts&.fetch(self, nil)
    end

    private def current_connected_network_flag_contexts
      Thread.current[FLAG_CONTEXTS_KEY]
    end

    private def connected_network_flag_contexts
      Thread.current[FLAG_CONTEXTS_KEY] ||= {}.compare_by_identity
    end
  end
end
