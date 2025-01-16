# frozen_string_literal: true

require_relative File.join("..", "support", "fixtures_helper")
require_relative "../spec_helper"

describe ReactOnRails::TestHelper::WebpackAssetsStatusChecker do
  describe "#stale_generated_webpack_files" do
    let(:source_path) { source_path_for(fixture_dirname) }
    let(:generated_assets_full_path) do
      compiled_js_dir_for(fixture_dirname)
    end
    let(:webpack_generated_files) { %w[manifest.json] }
    let(:server_bundle_js_file) { File.join(generated_assets_full_path, "server-bundle.js") }
    let(:client_bundle_js_file) { File.join(generated_assets_full_path, "client-bundle.js") }
    let(:checker) do
      described_class
        .new(generated_assets_full_path: generated_assets_full_path,
             source_path: source_path,
             webpack_generated_files: webpack_generated_files)
    end

    before do
      allow(ReactOnRails::PackerUtils).to receive(:check_manifest_not_cached).and_return(nil)
      allow(ReactOnRails::Utils).to receive(:generated_assets_full_path).and_return(generated_assets_full_path)
    end

    context "with Webpacker" do
      before do
        allow(ReactOnRails::PackerUtils).to receive(:using_packer?).and_return(true)
      end

      context "when compiled assets with manifest exist and are up-to-date" do
        let(:fixture_dirname) { "assets_with_manifest_exist" }

        before do
          allow(ReactOnRails::PackerUtils).to receive(:manifest_exists?).and_return(true)
          allow(ReactOnRails::Utils).to receive(:bundle_js_file_path)
            .with("manifest.json")
            .and_return(File.join(generated_assets_full_path, "manifest.json"))
          allow(ReactOnRails::Utils).to receive(:bundle_js_file_path)
            .with("server-bundle.js")
            .and_return(File.join(generated_assets_full_path, "server-bundle.js"))
          touch_files_in_dir(generated_assets_full_path)
        end

        specify { expect(checker.stale_generated_webpack_files).to eq([]) }
      end

      context "when using webpacker and manifest is missing" do
        let(:fixture_dirname) { "assets_with_missing_manifest" }

        before do
          allow(ReactOnRails::PackerUtils).to receive(:manifest_exists?).and_return(false)
        end

        specify { expect(checker.stale_generated_webpack_files).to eq(["manifest.json"]) }
      end

      context "when using webpacker, a missing server bundle without hash, and manifest is current" do
        let(:webpack_generated_files) { %w[manifest.json server-bundle.js] }
        let(:fixture_dirname) { "assets_with_manifest_exist_server_bundle_separate" }

        before do
          Packer = ReactOnRails::PackerUtils.packer # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
          allow(ReactOnRails::PackerUtils).to receive_messages(
            manifest_exists?: true,
            packer_public_output_path: generated_assets_full_path
          )
          allow(ReactOnRails.configuration).to receive(:server_bundle_js_file).and_return("server-bundle.js")
          allow(ReactOnRails::PackerUtils).to receive(:bundle_js_uri_from_packer)
            .with("manifest.json")
            .and_return(File.join(generated_assets_full_path, "manifest.json"))
          allow(ReactOnRails::PackerUtils).to receive(:bundle_js_uri_from_packer)
            .with("server-bundle.js")
            .and_raise(Packer::Manifest::MissingEntryError)
          touch_files_in_dir(generated_assets_full_path)
        end

        specify do
          expect(checker.stale_generated_webpack_files.first)
            .to match(/server-bundle\.js$/)
        end
      end
    end

    context "without Webpacker" do
      let(:webpack_generated_files) { %w[client-bundle.js server-bundle.js] }

      before do
        allow(ReactOnRails::PackerUtils).to receive(:using_packer?).and_return(false)
      end

      context "when compiled assets exist and are up-to-date" do
        let(:fixture_dirname) { "assets_exist" }

        before do
          touch_files_in_dir(generated_assets_full_path)
        end

        specify { expect(checker.stale_generated_webpack_files).to eq([]) }
      end

      context "when compiled assets don't exist" do
        let(:fixture_dirname) { "assets_no_exist" }

        specify do
          expect(checker.stale_generated_webpack_files)
            .to eq([client_bundle_js_file, server_bundle_js_file])
        end
      end

      context "when only server-bundle.js exists" do
        let(:fixture_dirname) { "assets_exist_only_server_bundle" }

        before do
          touch_files_in_dir(generated_assets_full_path)
        end

        specify do
          expect(checker.stale_generated_webpack_files)
            .to eq([client_bundle_js_file])
        end
      end

      context "when assets exist but are outdated" do
        let(:fixture_dirname) { "assets_outdated" }

        before { touch_files_in_dir(source_path) }

        specify do
          expect(checker.stale_generated_webpack_files)
            .to eq([client_bundle_js_file, server_bundle_js_file])
        end
      end
    end
  end

  def source_path_for(fixture_dirname)
    FixturesHelper.get_file(%W[webpack_assets #{fixture_dirname} client])
  end

  def compiled_js_dir_for(fixture_dirname)
    FixturesHelper.get_file(%W[webpack_assets #{fixture_dirname} compiled_js])
  end

  # Necessary for ensuring file mtimes of fixtures are correct
  def touch_files_in_dir(dir)
    `touch #{dir}/*`
  end
end
