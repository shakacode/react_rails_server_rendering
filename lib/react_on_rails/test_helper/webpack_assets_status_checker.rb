# frozen_string_literal: true

require "rake"
require "fileutils"
require "react_on_rails/utils"

# You can replace this implementation with your own for use by the
# ReactOnRails::TestHelper.ensure_assets_compiled helper
module ReactOnRails
  module TestHelper
    class WebpackAssetsStatusChecker
      include Utils::Required
      # source_path is typically configured in the (shaka/web)packer.yml file
      # for `source_path`
      # or for legacy React on Rails, it's /client, where all client files go
      attr_reader :source_path, :generated_assets_full_path

      def initialize(
        generated_assets_full_path: required("generated_assets_full_path"),
        source_path: required("source_path"),
        webpack_generated_files: required("webpack_generated_files")
      )
        @generated_assets_full_path = generated_assets_full_path
        @source_path = source_path
        @webpack_generated_files = webpack_generated_files
      end

      def stale_generated_webpack_files
        stale_generated_files(client_files)
      end

      def stale_generated_files(files)
        manifest_needed = ReactOnRails::PackerUtils.using_packer? &&
                          !ReactOnRails::PackerUtils.manifest_exists?

        return ["manifest.json"] if manifest_needed

        most_recent_mtime = Utils.find_most_recent_mtime(files)
        all_compiled_assets.each_with_object([]) do |webpack_generated_file, stale_gen_list|
          if !File.exist?(webpack_generated_file) ||
             File.mtime(webpack_generated_file) < most_recent_mtime
            stale_gen_list << webpack_generated_file
          end
          stale_gen_list
        end
      end

      private

      def all_compiled_assets
        @all_compiled_assets ||= begin
          webpack_generated_files = @webpack_generated_files.map do |bundle_name|
            if bundle_name == ReactOnRails.configuration.react_client_manifest_file
              ReactOnRails::Utils.react_client_manifest_file_path
            else
              ReactOnRails::Utils.bundle_js_file_path(bundle_name)
            end
          end

          if webpack_generated_files.present?
            webpack_generated_files
          else
            file_list = make_file_list(make_globs(generated_assets_full_path)).to_ary
            puts "V" * 80
            puts "Please define config.webpack_generated_files (array) so the test helper knows " \
                 "which files are required. If you are using Shakapacker, you typically need to only " \
                 "include 'manifest.json'."
            puts "Detected the possible following files to check for webpack compilation in " \
                 "#{generated_assets_full_path}"
            puts file_list.join("\n")
            puts "^" * 80
            file_list
          end
        end
      end

      def client_files
        @client_files ||= make_file_list(make_globs(source_path)).to_ary
      end

      def make_globs(dirs)
        Array(dirs).map { |dir| File.join(dir, "**", "*") }
      end

      def assets_exist?
        !all_compiled_assets.empty?
      end

      def make_file_list(glob)
        FileList.new(glob) do |fl|
          fl.exclude(%r{/node_modules})
          fl.exclude(".DS_Store")
          fl.exclude(".keep")
          fl.exclude("thumbs.db")
          fl.exclude(".")
          fl.exclude("..")
        end
      end
    end
  end
end
