# frozen_string_literal: true

require "fileutils"

module ReactOnRails
  # rubocop:disable Metrics/ClassLength
  class PacksGenerator
    CONTAINS_CLIENT_OR_SERVER_REGEX = /\.(server|client)($|\.)/
    MINIMUM_SHAKAPACKER_VERSION = [6, 5, 1].freeze

    def self.instance
      @instance ||= PacksGenerator.new
    end

    def generate_packs_if_stale
      return unless ReactOnRails.configuration.auto_load_bundle

      add_generated_pack_to_server_bundle
      are_generated_files_present_and_up_to_date = Dir.exist?(generated_packs_directory_path) &&
                                                   File.exist?(generated_server_bundle_file_path) &&
                                                   !stale_or_missing_packs?

      return if are_generated_files_present_and_up_to_date

      clean_generated_packs_directory
      generate_packs
    end

    private

    def generate_packs
      common_component_to_path.each_value { |component_path| create_pack(component_path) }
      client_component_to_path.each_value { |component_path| create_pack(component_path) }

      create_server_pack if ReactOnRails.configuration.server_bundle_js_file.present?
    end

    def create_pack(file_path)
      output_path = generated_pack_path(file_path)
      content = pack_file_contents(file_path)

      File.write(output_path, content)

      puts(Rainbow("Generated Packs: #{output_path}").yellow)
    end

    def first_js_statement_in_code(content)
      return "" if content.nil? || content.empty?
      
      start_index = 0
      content_length = content.length
      
      while start_index < content_length
        # Skip whitespace
        while start_index < content_length && content[start_index].match?(/\s/)
          start_index += 1
        end
        
        break if start_index >= content_length
        
        current_chars = content[start_index, 2]
        
        case current_chars
        when '//'
          # Single-line comment
          newline_index = content.index("\n", start_index)
          return "" if newline_index.nil?
          start_index = newline_index + 1
        when '/*'
          # Multi-line comment
          comment_end = content.index('*/', start_index)
          return "" if comment_end.nil?
          start_index = comment_end + 2
        else
          # Found actual content
          next_line_index = content.index("\n", start_index)
          return next_line_index ? content[start_index...next_line_index].strip : content[start_index..].strip
        end
      end

      ""
    end

    def is_client_entrypoint?(file_path)
      content = File.read(file_path)
      # has "use client" directive. It can be "use client" or 'use client'
      first_js_statement_in_code(content).match?(/^["']use client["'](?:;|\s|$)/)
    end

    def pack_file_contents(file_path)
      registered_component_name = component_name(file_path)
      register_as_server_component = ReactOnRails.configuration.auto_load_server_components && !is_client_entrypoint?(file_path)
      import_statement = register_as_server_component ? "" : "import #{registered_component_name} from '#{relative_component_path_from_generated_pack(file_path)}';"
      register_call = register_as_server_component ? "registerServerComponent(\"#{registered_component_name}\")" : "register({#{registered_component_name}})";

      <<~FILE_CONTENT
        import ReactOnRails from 'react-on-rails';
        #{import_statement}

        ReactOnRails.#{register_call};
      FILE_CONTENT
    end

    def create_server_pack
      File.write(generated_server_bundle_file_path, generated_server_pack_file_content)

      add_generated_pack_to_server_bundle
      puts(Rainbow("Generated Server Bundle: #{generated_server_bundle_file_path}").orange)
    end

    def generated_server_pack_file_content
      common_components_for_server_bundle = common_component_to_path.delete_if { |k| server_component_to_path.key?(k) }
      component_for_server_registration_to_path = common_components_for_server_bundle.merge(server_component_to_path)

      server_component_imports = component_for_server_registration_to_path.map do |name, component_path|
        "import #{name} from '#{relative_path(generated_server_bundle_file_path, component_path)}';"
      end

      components_to_register = component_for_server_registration_to_path.keys

      <<~FILE_CONTENT
        import ReactOnRails from 'react-on-rails';

        #{server_component_imports.join("\n")}

        ReactOnRails.register({#{components_to_register.join(",\n")}});
      FILE_CONTENT
    end

    def add_generated_pack_to_server_bundle
      return if ReactOnRails.configuration.make_generated_server_bundle_the_entrypoint

      relative_path_to_generated_server_bundle = relative_path(server_bundle_entrypoint,
                                                               generated_server_bundle_file_path)
      content = <<~FILE_CONTENT
        // import statement added by react_on_rails:generate_packs rake task
        import "./#{relative_path_to_generated_server_bundle}"
      FILE_CONTENT

      ReactOnRails::Utils.prepend_to_file_if_text_not_present(
        file: server_bundle_entrypoint,
        text_to_prepend: content,
        regex: %r{import ['"]\./#{relative_path_to_generated_server_bundle}['"]}
      )
    end

    def generated_server_bundle_file_path
      return server_bundle_entrypoint if ReactOnRails.configuration.make_generated_server_bundle_the_entrypoint

      generated_interim_server_bundle_path = server_bundle_entrypoint.sub(".js", "-generated.js")
      generated_server_bundle_file_name = component_name(generated_interim_server_bundle_path)
      source_entrypoint_parent = Pathname(ReactOnRails::PackerUtils.packer_source_entry_path).parent
      generated_nonentrypoints_path = "#{source_entrypoint_parent}/generated"

      FileUtils.mkdir_p(generated_nonentrypoints_path)
      "#{generated_nonentrypoints_path}/#{generated_server_bundle_file_name}.js"
    end

    def clean_generated_packs_directory
      FileUtils.rm_rf(generated_packs_directory_path)
      FileUtils.mkdir_p(generated_packs_directory_path)
    end

    def server_bundle_entrypoint
      Rails.root.join(ReactOnRails::PackerUtils.packer_source_entry_path,
                      ReactOnRails.configuration.server_bundle_js_file)
    end

    def generated_packs_directory_path
      source_entry_path = ReactOnRails::PackerUtils.packer_source_entry_path

      "#{source_entry_path}/generated"
    end

    def relative_component_path_from_generated_pack(ror_component_path)
      component_file_pathname = Pathname.new(ror_component_path)
      component_generated_pack_path = generated_pack_path(ror_component_path)
      generated_pack_pathname = Pathname.new(component_generated_pack_path)

      relative_path(generated_pack_pathname, component_file_pathname)
    end

    def relative_path(from, to)
      from_path = Pathname.new(from)
      to_path = Pathname.new(to)

      relative_path = to_path.relative_path_from(from_path)
      relative_path.sub("../", "")
    end

    def generated_pack_path(file_path)
      "#{generated_packs_directory_path}/#{component_name(file_path)}.js"
    end

    def component_name(file_path)
      basename = File.basename(file_path, File.extname(file_path))

      basename.sub(CONTAINS_CLIENT_OR_SERVER_REGEX, "")
    end

    def component_name_to_path(paths)
      paths.to_h { |path| [component_name(path), path] }
    end

    def common_component_to_path
      common_components_paths = Dir.glob("#{components_search_path}/*").grep_v(CONTAINS_CLIENT_OR_SERVER_REGEX)
      component_name_to_path(common_components_paths)
    end

    def client_component_to_path
      client_render_components_paths = Dir.glob("#{components_search_path}/*.client.*")
      client_specific_components = component_name_to_path(client_render_components_paths)

      duplicate_components = common_component_to_path.slice(*client_specific_components.keys)
      duplicate_components.each_key { |component| raise_client_component_overrides_common(component) }

      client_specific_components
    end

    def server_component_to_path
      server_render_components_paths = Dir.glob("#{components_search_path}/*.server.*")
      server_specific_components = component_name_to_path(server_render_components_paths)

      duplicate_components = common_component_to_path.slice(*server_specific_components.keys)
      duplicate_components.each_key { |component| raise_server_component_overrides_common(component) }

      server_specific_components.each_key do |k|
        raise_missing_client_component(k) unless client_component_to_path.key?(k)
      end

      server_specific_components
    end

    def components_search_path
      source_path = ReactOnRails::PackerUtils.packer_source_path

      "#{source_path}/**/#{ReactOnRails.configuration.components_subdirectory}"
    end

    def raise_client_component_overrides_common(component_name)
      msg = <<~MSG
        **ERROR** ReactOnRails: client specific definition for Component '#{component_name}' overrides the \
        common definition. Please delete the common definition and have separate server and client files. For more \
        information, please see https://www.shakacode.com/react-on-rails/docs/guides/file-system-based-automated-bundle-generation.md
      MSG

      raise ReactOnRails::Error, msg
    end

    def raise_server_component_overrides_common(component_name)
      msg = <<~MSG
        **ERROR** ReactOnRails: server specific definition for Component '#{component_name}' overrides the \
        common definition. Please delete the common definition and have separate server and client files. For more \
        information, please see https://www.shakacode.com/react-on-rails/docs/guides/file-system-based-automated-bundle-generation.md
      MSG

      raise ReactOnRails::Error, msg
    end

    def raise_missing_client_component(component_name)
      msg = <<~MSG
        **ERROR** ReactOnRails: Component '#{component_name}' is missing a client specific file. For more \
        information, please see https://www.shakacode.com/react-on-rails/docs/guides/file-system-based-automated-bundle-generation.md
      MSG

      raise ReactOnRails::Error, msg
    end

    def stale_or_missing_packs?
      component_files = common_component_to_path.values + client_component_to_path.values
      most_recent_mtime = Utils.find_most_recent_mtime(component_files).to_i

      component_files.each_with_object([]).any? do |file|
        path = generated_pack_path(file)
        !File.exist?(path) || File.mtime(path).to_i < most_recent_mtime
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
