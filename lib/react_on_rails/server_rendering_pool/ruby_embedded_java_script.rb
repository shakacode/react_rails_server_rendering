# frozen_string_literal: true

require "open-uri"
require "execjs"

module ReactOnRails
  module ServerRenderingPool
    # rubocop:disable Metrics/ClassLength
    class RubyEmbeddedJavaScript
      class << self
        def reset_pool
          options = {
            size: ReactOnRails.configuration.server_renderer_pool_size,
            timeout: ReactOnRails.configuration.server_renderer_timeout
          }
          @js_context_pool = ConnectionPool.new(options) { create_js_context }
        end

        def reset_pool_if_server_bundle_was_modified
          return unless ReactOnRails.configuration.development_mode

          if ReactOnRails::Utils.server_bundle_path_is_http?
            return if @server_bundle_url == ReactOnRails::Utils.server_bundle_js_file_path

            @server_bundle_url = ReactOnRails::Utils.server_bundle_js_file_path
          else
            file_mtime = File.mtime(ReactOnRails::Utils.server_bundle_js_file_path)
            @server_bundle_timestamp ||= file_mtime
            return if @server_bundle_timestamp == file_mtime

            @server_bundle_timestamp = file_mtime
          end
          ReactOnRails::ServerRenderingPool.reset_pool
        end

        # js_code: JavaScript expression that returns a string.
        # render_options: lib/react_on_rails/react_component/render_options.rb
        # Using these options:
        #    trace: saves the executed JS to a file, used in development
        #    logging_on_server: put on server logs, not just in browser console
        #
        # Returns a Hash:
        #   html: string of HTML for direct insertion on the page by evaluating js_code
        #   consoleReplayScript: script for replaying console
        #   hasErrors: true if server rendering errors
        # Note, js_code does not have to be based on React.
        # js_code MUST RETURN json stringify Object
        # Calling code will probably call 'html_safe' on return value before rendering to the view.
        # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        def exec_server_render_js(js_code, render_options, js_evaluator = nil)
          js_evaluator ||= self
          if render_options.trace
            @file_index ||= 1
            trace_js_code_used("Evaluating code to server render.", js_code,
                               "tmp/server-generated-#{@file_index % 10}.js")
            @file_index += 1
          end
          begin
            result = if render_options.stream? || render_options.rsc?
                       js_evaluator.eval_streaming_js(js_code, render_options)
                     else
                       js_evaluator.eval_js(js_code, render_options)
                     end
          rescue StandardError => err
            msg = <<~MSG
              Error evaluating server bundle. Check your webpack configuration.
              ===============================================================
              Caught error:
              #{err.message}
              ===============================================================
            MSG

            if err.message.include?("ReferenceError: self is not defined")
              msg << "\nError indicates that you may have code-splitting incorrectly enabled.\n"
            end
            raise ReactOnRails::Error, msg, err.backtrace
          end

          unless render_options.stream? || render_options.rsc?
            return parse_result_and_replay_console_messages(result,
                                                            render_options)
          end

          # Streamed component is returned as stream of strings.
          # We need to parse each chunk and replay the console messages.
          result.transform { |chunk| parse_result_and_replay_console_messages(chunk, render_options) }
        end
        # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

        def trace_js_code_used(msg, js_code, file_name = "tmp/server-generated.js", force: false)
          return unless ReactOnRails.configuration.trace || force

          # Set to anything to print generated code.
          File.write(file_name, js_code)
          msg = <<-MSG.strip_heredoc
            #{'Z' * 80}
            [react_on_rails] #{msg}
            JavaScript code used: #{file_name}
            #{'Z' * 80}
          MSG
          if force
            Rails.logger.error(msg)
          else
            Rails.logger.info(msg)
          end
        end

        def eval_js(js_code, _render_options)
          @js_context_pool.with do |js_context|
            js_context.eval(js_code)
          end
        end

        def read_bundle_js_code
          server_js_file = ReactOnRails::Utils.server_bundle_js_file_path
          if ReactOnRails::Utils.server_bundle_path_is_http?
            file_url_to_string(server_js_file)
          else
            File.read(server_js_file)
          end
        rescue StandardError => e
          msg = "You specified server rendering JS file: #{server_js_file}, but it cannot be " \
                "read. You may set the server_bundle_js_file in your configuration to be \"\" to " \
                "avoid this warning.\nError is: #{e}"
          raise ReactOnRails::Error, msg
        end

        def create_js_context
          return if ReactOnRails.configuration.server_bundle_js_file.blank?

          bundle_js_code = read_bundle_js_code
          base_js_code = <<~JS
            #{console_polyfill}
            #{execjs_timer_polyfills}
            #{bundle_js_code};
          JS

          file_name = "tmp/base_js_code.js"
          begin
            if ReactOnRails.configuration.trace
              Rails.logger.info do
                "[react_on_rails] Created JavaScript context with file " \
                  "#{ReactOnRails::Utils.server_bundle_js_file_path}"
              end
            end
            ExecJS.compile(base_js_code)
          rescue StandardError => e
            msg = "ERROR when compiling base_js_code! " \
                  "See file #{file_name} to " \
                  "correlate line numbers of error. Error is\n\n#{e.message}" \
                  "\n\n#{e.backtrace.join("\n")}"
            Rails.logger.error(msg)
            trace_js_code_used("Error when compiling JavaScript code for the context.", base_js_code,
                               file_name, force: true)
            raise e
          end
        end

        def execjs_timer_polyfills
          <<~JS
            function getStackTrace () {
              var stack;
              try {
                throw new Error('');
              }
              catch (error) {
                stack = error.stack || '';
              }
              stack = stack.split('\\n').map(function (line) { return line.trim(); });
              return stack.splice(stack[0] == 'Error' ? 2 : 1);
            }

            function setInterval() {
              #{undefined_for_exec_js_logging('setInterval')}
            }

            function setTimeout() {
              #{undefined_for_exec_js_logging('setTimeout')}
            }

            function clearTimeout() {
              #{undefined_for_exec_js_logging('clearTimeout')}
            }
          JS
        end

        def undefined_for_exec_js_logging(function_name)
          if ReactOnRails.configuration.trace
            "console.error('[React on Rails Rendering] #{function_name} is not defined for server rendering.');\n  " \
              "console.error(getStackTrace().join('\\n'));"
          else
            ""
          end
        end

        # Reimplement console methods for replaying on the client
        # Save a handle to the original console if needed.
        def console_polyfill
          <<~JS
            var debugConsole = console;
            var console = { history: [] };
            ['error', 'log', 'info', 'warn'].forEach(function (level) {
              console[level] = function () {
                var argArray = Array.prototype.slice.call(arguments);
                if (argArray.length > 0) {
                  argArray[0] = '[SERVER] ' + argArray[0];
                }
                console.history.push({level: level, arguments: argArray});
              };
            });
          JS
        end

        if defined?(ScoutApm)
          include ScoutApm::Tracer
          instrument_method :exec_server_render_js, type: "ReactOnRails", name: "ExecJs React Server Rendering"
        end

        private

        def file_url_to_string(url)
          response = Net::HTTP.get_response(URI.parse(url))
          content_type_header = response["content-type"]
          match = content_type_header.match(/\A.*; charset=(?<encoding>.*)\z/)
          encoding_type = match[:encoding]
          response.body.force_encoding(encoding_type)
        rescue StandardError => e
          msg = "file_url_to_string #{url} failed\nError is: #{e}"
          raise ReactOnRails::Error, msg
        end

        def parse_result_and_replay_console_messages(result_string, render_options)
          return { html: result_string } if render_options.rsc?

          result = nil
          begin
            result = JSON.parse(result_string)
          rescue JSON::ParserError => e
            raise ReactOnRails::JsonParseError.new(parse_error: e, json: result_string)
          end

          if render_options.logging_on_server
            console_script = result["consoleReplayScript"]
            console_script_lines = console_script.split("\n")
            # Regular expression to match console.log or console.error calls with SERVER prefix
            re = /console\.(?:log|error)\.apply\(console, \["\[SERVER\] (?<msg>.*)"\]\);/
            console_script_lines&.each do |line|
              match = re.match(line)
              # Log matched messages to Rails logger with react_on_rails prefix
              Rails.logger.info { "[react_on_rails] #{match[:msg]}" } if match
            end
          end
          result
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
