# frozen_string_literal: true

require "react_on_rails/utils"

module ReactOnRails
  module ReactComponent
    class RenderOptions
      include Utils::Required

      attr_accessor :request_digest

      NO_PROPS = {}.freeze

      # TODO: remove the required for named params
      def initialize(react_component_name: required("react_component_name"), options: required("options"))
        @react_component_name = react_component_name.camelize
        @options = options
      end

      attr_reader :react_component_name

      def throw_js_errors
        options.fetch(:throw_js_errors, false)
      end

      def props
        options.fetch(:props) { NO_PROPS }
      end

      def client_props
        props_extension = ReactOnRails.configuration.rendering_props_extension
        if props_extension.present?
          if props_extension.respond_to?(:adjust_props_for_client_side_hydration)
            return props_extension.adjust_props_for_client_side_hydration(react_component_name,
                                                                          props.clone)
          end

          raise ReactOnRails::Error, "ReactOnRails: your rendering_props_extension module is missing the " \
                                     "required adjust_props_for_client_side_hydration method & can not be used"
        end
        props
      end

      def random_dom_id
        retrieve_configuration_value_for(:random_dom_id)
      end

      def dom_id
        @dom_id ||= options.fetch(:id) do
          if random_dom_id
            generate_unique_dom_id
          else
            base_dom_id
          end
        end
      end

      def random_dom_id?
        return false if options[:id]

        return false unless random_dom_id

        true
      end

      def html_options
        options[:html_options].to_h
      end

      def prerender
        retrieve_configuration_value_for(:prerender)
      end

      def auto_load_bundle
        retrieve_configuration_value_for(:auto_load_bundle)
      end

      def trace
        retrieve_configuration_value_for(:trace)
      end

      def replay_console
        retrieve_configuration_value_for(:replay_console)
      end

      def raise_on_prerender_error
        retrieve_configuration_value_for(:raise_on_prerender_error)
      end

      def raise_non_shell_server_rendering_errors
        retrieve_react_on_rails_pro_config_value_for(:raise_non_shell_server_rendering_errors)
      end

      def logging_on_server
        retrieve_configuration_value_for(:logging_on_server)
      end

      def force_load
        retrieve_configuration_value_for(:force_load)
      end

      def to_s
        "{ react_component_name = #{react_component_name}, options = #{options}, request_digest = #{request_digest}"
      end

      def internal_option(key)
        options[key]
      end

      def set_option(key, value)
        options[key] = value
      end

      def stream?
        options[:stream?]
      end

      def rsc?
        options[:rsc?]
      end

      def store_dependencies
        options[:store_dependencies]
      end

      private

      attr_reader :options

      def base_dom_id
        "#{react_component_name}-react-component"
      end

      def generate_unique_dom_id
        "#{base_dom_id}-#{SecureRandom.uuid}"
      end

      def retrieve_configuration_value_for(key)
        options.fetch(key) do
          ReactOnRails.configuration.public_send(key)
        end
      end

      def retrieve_react_on_rails_pro_config_value_for(key)
        options.fetch(key) do
          return nil unless ReactOnRails::Utils.react_on_rails_pro?

          ReactOnRailsPro.configuration.public_send(key)
        end
      end
    end
  end
end
