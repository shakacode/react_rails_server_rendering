# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
# rubocop:disable Metrics/MethodLength
# NOTE:
# For any heredoc JS:
# 1. The white spacing in this file matters!
# 2. Keep all #{some_var} fully to the left so that all indentation is done evenly in that var
require "react_on_rails/prerender_error"
require "addressable/uri"
require "react_on_rails/utils"
require "react_on_rails/json_output"
require "active_support/concern"

module ReactOnRails
  module Helper
    include ReactOnRails::Utils::Required

    COMPONENT_HTML_KEY = "componentHtml"

    # react_component_name: can be a React function or class component or a "Render-Function".
    # "Render-Functions" differ from a React function in that they take two parameters, the
    #   props and the railsContext, like this:
    #
    #   let MyReactComponentApp = (props, railsContext) => <MyReactComponent {...props}/>;
    #
    #   Alternately, you can define the Render-Function with an additional property
    #   `.renderFunction = true`:
    #
    #   let MyReactComponentApp = (props) => <MyReactComponent {...props}/>;
    #   MyReactComponent.renderFunction = true;
    #
    #   Exposing the react_component_name is necessary to both a plain ReactComponent as well as
    #     a generator:
    #   See README.md for how to "register" your react components.
    #   See spec/dummy/client/app/packs/server-bundle.js and
    #     spec/dummy/client/app/packs/client-bundle.js for examples of this.
    #
    # options:
    #   props: Ruby Hash or JSON string which contains the properties to pass to the react object. Do
    #      not pass any props if you are separately initializing the store by the `redux_store` helper.
    #   prerender: <true/false> set to false when debugging!
    #   id: You can optionally set the id, or else a unique one is automatically generated.
    #   html_options: You can set other html attributes that will go on this component
    #   trace: <true/false> set to true to print additional debugging information in the browser
    #          default is true for development, off otherwise
    #   replay_console: <true/false> Default is true. False will disable echoing server rendering
    #                   logs to browser. While this can make troubleshooting server rendering difficult,
    #                   so long as you have the default configuration of logging_on_server set to
    #                   true, you'll still see the errors on the server.
    #   raise_on_prerender_error: <true/false> Default to false. True will raise exception on server
    #      if the JS code throws
    # Any other options are passed to the content tag, including the id.
    # random_dom_id can be set to override the default from the config/initializers. That's only
    # used if you have multiple instance of the same component on the Rails view.
    def react_component(component_name, options = {})
      internal_result = internal_react_component(component_name, options)
      server_rendered_html = internal_result[:result]["html"]
      console_script = internal_result[:result]["consoleReplayScript"]
      render_options = internal_result[:render_options]

      case server_rendered_html
      when String
        build_react_component_result_for_server_rendered_string(
          server_rendered_html: server_rendered_html,
          component_specification_tag: internal_result[:tag],
          console_script: console_script,
          render_options: render_options
        )
      when Hash
        msg = <<~MSG
          Use react_component_hash (not react_component) to return a Hash to your ruby view code. See
          https://github.com/shakacode/react_on_rails/blob/master/spec/dummy/client/app/startup/ReactHelmetServerApp.jsx
          for an example of the necessary javascript configuration.
        MSG
        raise ReactOnRails::Error, msg
      else
        class_name = server_rendered_html.class.name
        msg = <<~MSG
          ReactOnRails: server_rendered_html is expected to be a String or Hash for #{component_name}.
          Type is #{class_name}
          Value:
          #{server_rendered_html}

          If you're trying to use a Render-Function to return a Hash to your ruby view code, then use
          react_component_hash instead of react_component and see
          https://github.com/shakacode/react_on_rails/blob/master/spec/dummy/client/app/startup/ReactHelmetServerApp.jsx
          for an example of the JavaScript code.
        MSG
        raise ReactOnRails::Error, msg
      end
    end

    # Streams a server-side rendered React component using React's `renderToPipeableStream`.
    # Supports React 18 features like Suspense, concurrent rendering, and selective hydration.
    # Enables progressive rendering and improved performance for large components.
    #
    # Note: This function can only be used with React on Rails Pro.
    # The view that uses this function must be rendered using the
    # `stream_view_containing_react_components` method from the React on Rails Pro gem.
    #
    # Example of an async React component that can benefit from streaming:
    #
    # const AsyncComponent = async () => {
    #   const data = await fetchData();
    #   return <div>{data}</div>;
    # };
    #
    # function App() {
    #   return (
    #     <Suspense fallback={<div>Loading...</div>}>
    #       <AsyncComponent />
    #     </Suspense>
    #   );
    # }
    #
    # @param [String] component_name Name of your registered component
    # @param [Hash] options Options for rendering
    # @option options [Hash] :props Props to pass to the react component
    # @option options [String] :dom_id DOM ID of the component container
    # @option options [Hash] :html_options Options passed to content_tag
    # @option options [Boolean] :prerender Set to false to disable server-side rendering
    # @option options [Boolean] :trace Set to true to add extra debugging information to the HTML
    # @option options [Boolean] :raise_on_prerender_error Set to true to raise exceptions during server-side rendering
    # Any other options are passed to the content tag, including the id.
    def stream_react_component(component_name, options = {})
      options = options.merge(force_load: true) unless options.key?(:force_load)
      run_stream_inside_fiber do
        internal_stream_react_component(component_name, options)
      end
    end

    def rsc_react_component(component_name, options = {})
      run_stream_inside_fiber do
        internal_rsc_react_component(component_name, options)
      end
    end

    # react_component_hash is used to return multiple HTML strings for server rendering, such as for
    # adding meta-tags to a page.
    # It is exactly like react_component except for the following:
    # 1. prerender: true is automatically added, as this method doesn't make sense for client only
    #    rendering.
    # 2. Your JavaScript Render-Function for server rendering must return an Object rather than a React component.
    # 3. Your view code must expect an object and not a string.
    #
    # Here is an example of the view code:
    #    <% react_helmet_app = react_component_hash("ReactHelmetApp", prerender: true,
    #                                               props: { helloWorldData: { name: "Mr. Server Side Rendering"}},
    #                                               id: "react-helmet-0", trace: true) %>
    #    <% content_for :title do %>
    #      <%= react_helmet_app['title'] %>
    #    <% end %>
    #    <%= react_helmet_app["componentHtml"] %>
    #
    def react_component_hash(component_name, options = {})
      options[:prerender] = true
      internal_result = internal_react_component(component_name, options)
      server_rendered_html = internal_result[:result]["html"]
      console_script = internal_result[:result]["consoleReplayScript"]
      render_options = internal_result[:render_options]

      if server_rendered_html.is_a?(String) && internal_result[:result]["hasErrors"]
        server_rendered_html = { COMPONENT_HTML_KEY => internal_result[:result]["html"] }
      end

      if server_rendered_html.is_a?(Hash)
        build_react_component_result_for_server_rendered_hash(
          server_rendered_html: server_rendered_html,
          component_specification_tag: internal_result[:tag],
          console_script: console_script,
          render_options: render_options
        )
      else
        msg = <<~MSG
          Render-Function used by react_component_hash for #{component_name} is expected to return
          an Object. See https://github.com/shakacode/react_on_rails/blob/master/spec/dummy/client/app/startup/ReactHelmetServerApp.jsx
          for an example of the JavaScript code.
          Note, your Render-Function must either take 2 params or have the property
          `.renderFunction = true` added to it to distinguish it from a React Function Component.
        MSG
        raise ReactOnRails::Error, msg
      end
    end

    # Separate initialization of store from react_component allows multiple react_component calls to
    # use the same Redux store.
    #
    # NOTE: This technique not recommended as it prevents dynamic code splitting for performance.
    # Instead, you should use the standard react_component view helper.
    #
    # store_name: name of the store, corresponding to your call to ReactOnRails.registerStores in your
    #             JavaScript code.
    # props: Ruby Hash or JSON string which contains the properties to pass to the redux store.
    # Options
    #    defer: false -- pass as true if you wish to render this below your component.
    #    force_load: false -- pass as true if you wish to hydrate this store immediately instead of
    #                        waiting for the page to load.
    def redux_store(store_name, props: {}, defer: false, force_load: false)
      redux_store_data = { store_name: store_name,
                           props: props,
                           force_load: force_load }
      if defer
        registered_stores_defer_render << redux_store_data
        "YOU SHOULD NOT SEE THIS ON YOUR VIEW -- Uses as a code block, like <% redux_store %> " \
          "and not <%= redux store %>"
      else
        registered_stores << redux_store_data
        result = render_redux_store_data(redux_store_data)
        prepend_render_rails_context(result)
      end
    end

    # Place this view helper (no parameters) at the end of your shared layout. This tell
    # ReactOnRails where to client render the redux store hydration data. Since we're going
    # to be setting up the stores in the controllers, we need to know where on the view to put the
    # client side rendering of this hydration data, which is a hidden div with a matching class
    # that contains a data props.
    def redux_store_hydration_data
      return if registered_stores_defer_render.blank?

      registered_stores_defer_render.reduce(+"") do |accum, redux_store_data|
        accum << render_redux_store_data(redux_store_data)
      end.html_safe
    end

    def sanitized_props_string(props)
      ReactOnRails::JsonOutput.escape(props.is_a?(String) ? props : props.to_json)
    end

    # Helper method to take javascript expression and returns the output from evaluating it.
    # If you have more than one line that needs to be executed, wrap it in an IIFE.
    # JS exceptions are caught and console messages are handled properly.
    # Options include:{ prerender:, trace:, raise_on_prerender_error:, throw_js_errors: }
    def server_render_js(js_expression, options = {})
      render_options = ReactOnRails::ReactComponent::RenderOptions
                       .new(react_component_name: "generic-js", options: options)

      js_code = <<-JS.strip_heredoc
      (function() {
        var htmlResult = '';
        var consoleReplayScript = '';
        var hasErrors = false;
        var renderingError = null;
        var renderingErrorObject = {};

        try {
          htmlResult =
            (function() {
              return #{js_expression};
            })();
        } catch(e) {
          renderingError = e;
          if (#{render_options.throw_js_errors}) {
            throw e;
          }
          htmlResult = ReactOnRails.handleError({e: e, name: null,
            jsCode: '#{escape_javascript(js_expression)}', serverSide: true});
          hasErrors = true;
          renderingErrorObject = {
            message: renderingError.message,
            stack: renderingError.stack,
          }
        }

        consoleReplayScript = ReactOnRails.buildConsoleReplay();

        return JSON.stringify({
            html: htmlResult,
            consoleReplayScript: consoleReplayScript,
            hasErrors: hasErrors,
            renderingError: renderingErrorObject
        });

      })()
      JS

      result = ReactOnRails::ServerRenderingPool
               .server_render_js_with_console_logging(js_code, render_options)

      html = result["html"]
      console_log_script = result["consoleLogScript"]
      raw("#{html}#{render_options.replay_console ? console_log_script : ''}")
    rescue ExecJS::ProgramError => err
      raise ReactOnRails::PrerenderError.new(component_name: "N/A (server_render_js called)",
                                             err: err,
                                             js_code: js_code)
    end

    def json_safe_and_pretty(hash_or_string)
      return "{}" if hash_or_string.nil?

      unless hash_or_string.is_a?(String) || hash_or_string.is_a?(Hash)
        raise ReactOnRails::Error, "#{__method__} only accepts String or Hash as argument " \
                                   "(#{hash_or_string.class} given)."
      end

      json_value = hash_or_string.is_a?(String) ? hash_or_string : hash_or_string.to_json

      ReactOnRails::JsonOutput.escape(json_value)
    end

    # This is the definitive list of the default values used for the rails_context, which is the
    # second parameter passed to both component and store Render-Functions.
    # This method can be called from views and from the controller, as `helpers.rails_context`
    #
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    def rails_context(server_side: true)
      # ALERT: Keep in sync with node_package/src/types/index.ts for the properties of RailsContext
      @rails_context ||= begin
        result = {
          railsEnv: Rails.env,
          inMailer: in_mailer?,
          # Locale settings
          i18nLocale: I18n.locale,
          i18nDefaultLocale: I18n.default_locale,
          rorVersion: ReactOnRails::VERSION,
          # TODO: v13 just use the version if existing
          rorPro: ReactOnRails::Utils.react_on_rails_pro?
        }
        if ReactOnRails::Utils.react_on_rails_pro?
          result[:rorProVersion] = ReactOnRails::Utils.react_on_rails_pro_version
        end

        if defined?(request) && request.present?
          # Check for encoding of the request's original_url and try to force-encoding the
          # URLs as UTF-8. This situation can occur in browsers that do not encode the
          # entire URL as UTF-8 already, mostly on the Windows platform (IE11 and lower).
          original_url_normalized = request.original_url
          if original_url_normalized.encoding == Encoding::BINARY
            original_url_normalized = original_url_normalized.force_encoding(Encoding::ISO_8859_1)
                                                             .encode(Encoding::UTF_8)
          end

          # Using Addressable instead of standard URI to better deal with
          # non-ASCII characters (see https://github.com/shakacode/react_on_rails/pull/405)
          uri = Addressable::URI.parse(original_url_normalized)
          # uri = Addressable::URI.parse("http://foo.com:3000/posts?id=30&limit=5#time=1305298413")

          result.merge!(
            # URL settings
            href: uri.to_s,
            location: "#{uri.path}#{uri.query.present? ? "?#{uri.query}" : ''}",
            scheme: uri.scheme, # http
            host: uri.host, # foo.com
            port: uri.port,
            pathname: uri.path, # /posts
            search: uri.query, # id=30&limit=5
            httpAcceptLanguage: request.env["HTTP_ACCEPT_LANGUAGE"]
          )
        end
        if ReactOnRails.configuration.rendering_extension
          custom_context = ReactOnRails.configuration.rendering_extension.custom_context(self)
          result.merge!(custom_context) if custom_context
        end
        result
      end

      @rails_context.merge(serverSide: server_side)
    end

    def load_pack_for_generated_component(react_component_name, render_options)
      return unless render_options.auto_load_bundle

      ReactOnRails::PackerUtils.raise_nested_entries_disabled unless ReactOnRails::PackerUtils.nested_entries?
      if Rails.env.development?
        is_component_pack_present = File.exist?(generated_components_pack_path(react_component_name))
        raise_missing_autoloaded_bundle(react_component_name) unless is_component_pack_present
      end
      append_javascript_pack_tag("generated/#{react_component_name}",
                                 defer: ReactOnRails.configuration.defer_generated_component_packs)
      append_stylesheet_pack_tag("generated/#{react_component_name}")
    end

    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

    private

    def run_stream_inside_fiber
      unless ReactOnRails::Utils.react_on_rails_pro?
        raise ReactOnRails::Error,
              "You must use React on Rails Pro to use the stream_react_component method."
      end

      if @rorp_rendering_fibers.nil?
        raise ReactOnRails::Error,
              "You must call stream_view_containing_react_components to render the view containing the react component"
      end

      rendering_fiber = Fiber.new do
        stream = yield
        stream.each_chunk do |chunk|
          Fiber.yield chunk
        end
      end

      @rorp_rendering_fibers << rendering_fiber

      # return the first chunk of the fiber
      # It contains the initial html of the component
      # all updates will be appended to the stream sent to browser
      rendering_fiber.resume
    end

    def registered_stores
      @registered_stores ||= []
    end

    def registered_stores_defer_render
      @registered_stores_defer_render ||= []
    end

    def registered_stores_including_deferred
      registered_stores + registered_stores_defer_render
    end

    def create_render_options(react_component_name, options)
      # If no store dependencies are passed, default to all registered stores up till now
      options[:store_dependencies] ||= registered_stores_including_deferred.map { |store| store[:store_name] }
      ReactOnRails::ReactComponent::RenderOptions.new(react_component_name: react_component_name,
                                                      options: options)
    end

    def internal_stream_react_component(component_name, options = {})
      options = options.merge(stream?: true)
      result = internal_react_component(component_name, options)
      build_react_component_result_for_server_streamed_content(
        rendered_html_stream: result[:result],
        component_specification_tag: result[:tag],
        render_options: result[:render_options]
      )
    end

    def internal_rsc_react_component(react_component_name, options = {})
      options = options.merge(rsc?: true)
      render_options = create_render_options(react_component_name, options)
      json_stream = server_rendered_react_component(render_options)
      json_stream.transform do |chunk|
        "#{chunk.to_json}\n".html_safe
      end
    end

    def generated_components_pack_path(component_name)
      "#{ReactOnRails::PackerUtils.packer_source_entry_path}/generated/#{component_name}.js"
    end

    def build_react_component_result_for_server_rendered_string(
      server_rendered_html: required("server_rendered_html"),
      component_specification_tag: required("component_specification_tag"),
      console_script: required("console_script"),
      render_options: required("render_options")
    )
      content_tag_options = render_options.html_options
      if content_tag_options.key?(:tag)
        content_tag_options_html_tag = content_tag_options[:tag]
        content_tag_options.delete(:tag)
      else
        content_tag_options_html_tag = "div"
      end
      content_tag_options[:id] = render_options.dom_id

      rendered_output = content_tag(content_tag_options_html_tag.to_sym,
                                    server_rendered_html.html_safe,
                                    content_tag_options)

      result_console_script = render_options.replay_console ? console_script : ""
      result = compose_react_component_html_with_spec_and_console(
        component_specification_tag, rendered_output, result_console_script
      )

      prepend_render_rails_context(result)
    end

    def build_react_component_result_for_server_streamed_content(
      rendered_html_stream:,
      component_specification_tag:,
      render_options:
    )
      is_first_chunk = true
      rendered_html_stream.transform do |chunk_json_result|
        if is_first_chunk
          is_first_chunk = false
          build_react_component_result_for_server_rendered_string(
            server_rendered_html: chunk_json_result["html"],
            component_specification_tag: component_specification_tag,
            console_script: chunk_json_result["consoleReplayScript"],
            render_options: render_options
          )
        else
          result_console_script = render_options.replay_console ? chunk_json_result["consoleReplayScript"] : ""
          # No need to prepend component_specification_tag or add rails context again
          # as they're already included in the first chunk
          compose_react_component_html_with_spec_and_console(
            "", chunk_json_result["html"], result_console_script
          )
        end
      end
    end

    def build_react_component_result_for_server_rendered_hash(
      server_rendered_html: required("server_rendered_html"),
      component_specification_tag: required("component_specification_tag"),
      console_script: required("console_script"),
      render_options: required("render_options")
    )
      content_tag_options = render_options.html_options
      content_tag_options[:id] = render_options.dom_id

      unless server_rendered_html[COMPONENT_HTML_KEY]
        raise ReactOnRails::Error, "server_rendered_html hash expected to contain \"#{COMPONENT_HTML_KEY}\" key."
      end

      rendered_output = content_tag(:div,
                                    server_rendered_html[COMPONENT_HTML_KEY].html_safe,
                                    content_tag_options)

      result_console_script = render_options.replay_console ? console_script : ""
      result = compose_react_component_html_with_spec_and_console(
        component_specification_tag, rendered_output, result_console_script
      )

      # Other HTML strings need to be marked as html_safe too:
      server_rendered_hash_except_component = server_rendered_html.except(COMPONENT_HTML_KEY)
      server_rendered_hash_except_component.each do |key, html_string|
        server_rendered_hash_except_component[key] = html_string.html_safe
      end

      result_with_rails_context = prepend_render_rails_context(result)
      { COMPONENT_HTML_KEY => result_with_rails_context }.merge(
        server_rendered_hash_except_component
      )
    end

    def compose_react_component_html_with_spec_and_console(component_specification_tag, rendered_output,
                                                           console_script)
      # IMPORTANT: Ensure that we mark string as html_safe to avoid escaping.
      html_content = <<~HTML
        #{rendered_output}
              #{component_specification_tag}
              #{console_script}
      HTML
      html_content.strip.html_safe
    end

    def rails_context_if_not_already_rendered
      return "" if @rendered_rails_context

      data = rails_context(server_side: false)

      @rendered_rails_context = true

      content_tag(:script,
                  json_safe_and_pretty(data).html_safe,
                  type: "application/json",
                  id: "js-react-on-rails-context")
    end

    # prepend the rails_context if not yet applied
    def prepend_render_rails_context(render_value)
      "#{rails_context_if_not_already_rendered}\n#{render_value}".strip.html_safe
    end

    def internal_react_component(react_component_name, options = {})
      # Create the JavaScript and HTML to allow either client or server rendering of the
      # react_component.
      #
      # Create the JavaScript setup of the global to initialize the client rendering
      # (re-hydrate the data). This enables react rendered on the client to see that the
      # server has already rendered the HTML.

      render_options = create_render_options(react_component_name, options)

      # Setup the page_loaded_js, which is the same regardless of prerendering or not!
      # The reason is that React is smart about not doing extra work if the server rendering did its job.
      component_specification_tag = content_tag(:script,
                                                json_safe_and_pretty(render_options.client_props).html_safe,
                                                type: "application/json",
                                                class: "js-react-on-rails-component",
                                                id: "js-react-on-rails-component-#{render_options.dom_id}",
                                                "data-component-name" => render_options.react_component_name,
                                                "data-trace" => (render_options.trace ? true : nil),
                                                "data-dom-id" => render_options.dom_id,
                                                "data-store-dependencies" => render_options.store_dependencies.to_json,
                                                "data-force-load" => (render_options.force_load ? true : nil))

      if render_options.force_load
        component_specification_tag.concat(
          content_tag(:script, %(
ReactOnRails.reactOnRailsComponentLoaded('#{render_options.dom_id}');
          ).html_safe)
        )
      end

      load_pack_for_generated_component(react_component_name, render_options)
      # Create the HTML rendering part
      result = server_rendered_react_component(render_options)

      {
        render_options: render_options,
        tag: component_specification_tag,
        result: result
      }
    end

    def render_redux_store_data(redux_store_data)
      store_hydration_data = content_tag(:script,
                                         json_safe_and_pretty(redux_store_data[:props]).html_safe,
                                         type: "application/json",
                                         "data-js-react-on-rails-store" => redux_store_data[:store_name].html_safe,
                                         "data-force-load" => (redux_store_data[:force_load] ? true : nil))

      if redux_store_data[:force_load]
        store_hydration_data.concat(
          content_tag(:script, <<~JS.strip_heredoc.html_safe
            ReactOnRails.reactOnRailsStoreLoaded('#{redux_store_data[:store_name]}');
          JS
          )
        )
      end

      prepend_render_rails_context(store_hydration_data)
    end

    def props_string(props)
      props.is_a?(String) ? props : props.to_json
    end

    def raise_prerender_error(json_result, react_component_name, props, js_code)
      raise ReactOnRails::PrerenderError.new(
        component_name: react_component_name,
        props: sanitized_props_string(props),
        err: nil,
        js_code: js_code,
        console_messages: json_result["consoleReplayScript"]
      )
    end

    def should_raise_streaming_prerender_error?(chunk_json_result, render_options)
      chunk_json_result["hasErrors"] &&
        (if chunk_json_result["isShellReady"]
           render_options.raise_non_shell_server_rendering_errors
         else
           render_options.raise_on_prerender_error
         end)
    end

    # Returns object with values that are NOT html_safe!
    def server_rendered_react_component(render_options) # rubocop:disable Metrics/CyclomaticComplexity
      return { "html" => "", "consoleReplayScript" => "" } unless render_options.prerender

      react_component_name = render_options.react_component_name
      props = render_options.props

      # On server `location` option is added (`location = request.fullpath`)
      # React Router needs this to match the current route

      # Make sure that we use up-to-date bundle file used for server rendering, which is defined
      # by config file value for config.server_bundle_js_file
      ReactOnRails::ServerRenderingPool.reset_pool_if_server_bundle_was_modified

      # Since this code is not inserted on a web page, we don't need to escape props
      #
      # However, as JSON (returned from `props_string(props)`) isn't JavaScript,
      # but we want treat it as such, we need to compensate for the difference.
      #
      # \u2028 and \u2029 are valid characters in strings in JSON, but are treated
      # as newline separators in JavaScript. As no newlines are allowed in
      # strings in JavaScript, this causes an exception.
      #
      # We fix this by replacing these unicode characters with their escaped versions.
      # This should be safe, as the only place they can appear is in strings anyway.
      #
      # Read more here: http://timelessrepo.com/json-isnt-a-javascript-subset

      js_code = ReactOnRails::ServerRenderingJsCode.server_rendering_component_js_code(
        props_string: props_string(props).gsub("\u2028", '\u2028').gsub("\u2029", '\u2029'),
        rails_context: rails_context(server_side: true).to_json,
        redux_stores: initialize_redux_stores(render_options),
        react_component_name: react_component_name,
        render_options: render_options
      )

      begin
        result = ReactOnRails::ServerRenderingPool.server_render_js_with_console_logging(js_code, render_options)
      rescue StandardError => err
        # This error came from the renderer
        raise ReactOnRails::PrerenderError.new(component_name: react_component_name,
                                               # Sanitize as this might be browser logged
                                               props: sanitized_props_string(props),
                                               err: err,
                                               js_code: js_code)
      end

      if render_options.stream? || render_options.rsc?
        result.transform do |chunk_json_result|
          if should_raise_streaming_prerender_error?(chunk_json_result, render_options)
            raise_prerender_error(chunk_json_result, react_component_name, props, js_code)
          end
          # It doesn't make any transformation, it listens and raises error if a chunk has errors
          chunk_json_result
        end
      elsif result["hasErrors"] && render_options.raise_on_prerender_error
        raise_prerender_error(result, react_component_name, props, js_code)
      end

      result
    end

    def initialize_redux_stores(render_options)
      result = +<<-JS
      ReactOnRails.clearHydratedStores();
      JS

      store_dependencies = render_options.store_dependencies
      return result unless store_dependencies.present?

      declarations = +"var reduxProps, store, storeGenerator;\n"
      store_objects = registered_stores_including_deferred.select do |store|
        store_dependencies.include?(store[:store_name])
      end

      result << store_objects.each_with_object(declarations) do |redux_store_data, memo|
        store_name = redux_store_data[:store_name]
        props = props_string(redux_store_data[:props])
        memo << <<-JS.strip_heredoc
        reduxProps = #{props};
        storeGenerator = ReactOnRails.getStoreGenerator('#{store_name}');
        store = storeGenerator(reduxProps, railsContext);
        ReactOnRails.setStore('#{store_name}', store);
        JS
      end
      result
    end

    def replay_console_option(val)
      val.nil? ? ReactOnRails.configuration.replay_console : val
    end

    def in_mailer?
      return false unless defined?(controller)
      return false unless defined?(ActionMailer::Base)

      controller.is_a?(ActionMailer::Base)
    end

    if defined?(ScoutApm)
      include ScoutApm::Tracer
      instrument_method :react_component, type: "ReactOnRails", name: "react_component"
      instrument_method :react_component_hash, type: "ReactOnRails", name: "react_component_hash"
    end

    def raise_missing_autoloaded_bundle(react_component_name)
      msg = <<~MSG
        **ERROR** ReactOnRails: Component "#{react_component_name}" is configured as "auto_load_bundle: true"
        but the generated component entrypoint, which should have been at #{generated_components_pack_path(react_component_name)},
        is missing. You might want to check that this component is in a directory named "#{ReactOnRails.configuration.components_subdirectory}"
        & that "bundle exec rake react_on_rails:generate_packs" has been run.
      MSG

      raise ReactOnRails::Error, msg
    end
  end
end
# rubocop:enable Metrics/ModuleLength
# rubocop:enable Metrics/MethodLength
