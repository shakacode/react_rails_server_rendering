# frozen_string_literal: true

require_relative "spec_helper"
require ReactOnRails::PackerUtils.packer_type

# rubocop:disable Metrics/ModuleLength

module ReactOnRails
  RSpec.describe Configuration do
    let(:existing_path) { Pathname.new(Dir.mktmpdir) }
    let(:not_existing_path) { "/path/to/#{SecureRandom.hex(4)}" }
    let(:using_packer) { false }

    before do
      allow(ReactOnRails::PackerUtils).to receive(:using_packer?).and_return(using_packer)
      allow(ReactOnRails::Utils).to receive(:gem_available?).and_call_original
      allow(ReactOnRails::Utils).to receive(:gem_available?).with("webpacker").and_return(false)
      ReactOnRails.instance_variable_set(:@configuration, nil)
    end

    after do
      ReactOnRails.instance_variable_set(:@configuration, nil)
    end

    describe "generated_assets_dir" do
      let(:using_packer) { true }
      let(:packer_public_output_path) do
        File.expand_path(File.join(Rails.root, "public/webpack/dev"))
      end

      before do
        allow(Rails).to receive(:root).and_return(File.expand_path("."))
        allow(ReactOnRails::PackerUtils).to receive_message_chain("packer.config.public_output_path")
          .and_return(packer_public_output_path)
      end

      it "does not throw if the generated assets dir is blank with webpacker" do
        expect do
          ReactOnRails.configure do |config|
            config.generated_assets_dir = ""
          end
        end.not_to raise_error
      end

      it "does not throw if the packer_public_output_path does match the generated assets dir" do
        expect do
          ReactOnRails.configure do |config|
            config.generated_assets_dir = "public/webpack/dev"
          end
        end.not_to raise_error
      end

      it "does throw if the packer_public_output_path does not match the generated assets dir" do
        expect do
          ReactOnRails.configure do |config|
            config.generated_assets_dir = "public/webpack/other"
          end
        end.to raise_error(ReactOnRails::Error, /does not match the value for public_output_path/)
      end
    end

    describe ".server_render_method" do
      it "does not throw if the server render method is blank" do
        expect do
          ReactOnRails.configure do |config|
            config.server_render_method = ""
          end
        end.not_to raise_error
      end

      it "throws if the server render method is node" do
        expect do
          ReactOnRails.configure do |config|
            config.server_render_method = "node"
          end
        end.to raise_error(ReactOnRails::Error, /invalid value for `config.server_render_method`/)
      end
    end

    describe ".build_production_command" do
      context "when using Shakapacker 6", if: ReactOnRails::PackerUtils.packer_type != "shakapacker" do
        it "fails when \"shakapacker_precompile\" is truly and \"build_production_command\" is truly" do
          allow(Webpacker).to receive_message_chain("config.webpacker_precompile?")
            .and_return(true)
          expect do
            ReactOnRails.configure do |config|
              config.build_production_command = "RAILS_ENV=production NODE_ENV=production bin/shakapacker"
            end
          end.to raise_error(ReactOnRails::Error, /webpacker_precompile: false/)
        end

        it "doesn't fail when \"shakapacker_precompile\" is falsy and \"build_production_command\" is truly" do
          allow(Webpacker).to receive_message_chain("config.webpacker_precompile?")
            .and_return(false)
          expect do
            ReactOnRails.configure do |config|
              config.build_production_command = "RAILS_ENV=production NODE_ENV=production bin/shakapacker"
            end
          end.not_to raise_error
        end

        it "doesn't fail when \"shakapacker_precompile\" is truly and \"build_production_command\" is falsy" do
          allow(Webpacker).to receive_message_chain("config.webpacker_precompile?")
            .and_return(true)
          expect do
            ReactOnRails.configure {} # rubocop:disable-line Lint/EmptyBlock
          end.not_to raise_error
        end

        it "doesn't fail when \"shakapacker_precompile\" is falsy and \"build_production_command\" is falsy" do
          allow(Webpacker).to receive_message_chain("config.webpacker_precompile?")
            .and_return(false)
          expect do
            ReactOnRails.configure {} # rubocop:disable-line Lint/EmptyBlock
          end.not_to raise_error
        end
      end

      context "when using Shakapacker 8", if: ReactOnRails::PackerUtils.packer_type == "shakapacker" do
        it "fails when \"shakapacker_precompile\" is truly and \"build_production_command\" is truly" do
          allow(Shakapacker).to receive_message_chain("config.shakapacker_precompile?")
            .and_return(true)
          expect do
            ReactOnRails.configure do |config|
              config.build_production_command = "RAILS_ENV=production NODE_ENV=production bin/shakapacker"
            end
          end.to raise_error(ReactOnRails::Error, /shakapacker_precompile: false/)
        end

        it "doesn't fail when \"shakapacker_precompile\" is falsy and \"build_production_command\" is truly" do
          allow(Shakapacker).to receive_message_chain("config.shakapacker_precompile?")
            .and_return(false)
          expect do
            ReactOnRails.configure do |config|
              config.build_production_command = "RAILS_ENV=production NODE_ENV=production bin/shakapacker"
            end
          end.not_to raise_error
        end

        it "doesn't fail when \"shakapacker_precompile\" is truly and \"build_production_command\" is falsy" do
          allow(Shakapacker).to receive_message_chain("config.shakapacker_precompile?")
            .and_return(true)
          expect do
            ReactOnRails.configure {} # rubocop:disable-line Lint/EmptyBlock
          end.not_to raise_error
        end

        it "doesn't fail when \"shakapacker_precompile\" is falsy and \"build_production_command\" is falsy" do
          allow(Shakapacker).to receive_message_chain("config.shakapacker_precompile?")
            .and_return(false)
          expect do
            ReactOnRails.configure {} # rubocop:disable-line Lint/EmptyBlock
          end.not_to raise_error
        end
      end
    end

    describe ".i18n_dir" do
      let(:i18n_dir) { existing_path }

      it "passes if directory exists" do
        expect do
          ReactOnRails.configure do |config|
            config.i18n_dir = i18n_dir
          end
        end.not_to raise_error
      end

      it "fails with empty string value" do
        expect do
          ReactOnRails.configure do |config|
            config.i18n_dir = ""
          end
        end.not_to raise_error
        expect do
          ReactOnRails::Locales.compile
        end.to raise_error(ReactOnRails::Error, /invalid value for `config\.i18n_dir`/)
      end

      it "fails with not existing directory" do
        expect do
          ReactOnRails.configure do |config|
            config.i18n_dir = not_existing_path
          end
        end.not_to raise_error
        expect do
          ReactOnRails::Locales.compile
        end.to raise_error(ReactOnRails::Error, /invalid value for `config\.i18n_dir`/)
      end
    end

    describe ".i18n_yml_dir" do
      let(:i18n_yml_dir) { existing_path }

      it "passes if directory exists" do
        expect do
          ReactOnRails.configure do |config|
            config.i18n_yml_dir = i18n_yml_dir
          end
        end.not_to raise_error
        expect do
          ReactOnRails::Locales.compile
        end.not_to raise_error
      end

      it "fails with empty string value" do
        expect do
          ReactOnRails.configure do |config|
            config.i18n_yml_dir = ""
          end
        end.not_to raise_error
        expect do
          ReactOnRails::Locales.compile
        end.to raise_error(ReactOnRails::Error, /invalid value for `config\.i18n_yml_dir`/)
      end

      it "fails with not existing directory" do
        expect do
          ReactOnRails.configure do |config|
            config.i18n_yml_dir = not_existing_path
          end
        end.not_to raise_error
        expect do
          ReactOnRails::Locales.compile
        end.to raise_error(ReactOnRails::Error, /invalid value for `config\.i18n_yml_dir`/)
      end
    end

    it "changes the configuration of the gem, such as setting the prerender option to false" do
      ReactOnRails.configure do |config|
        config.server_bundle_js_file = "server.js"
        config.prerender = false
      end

      expect(ReactOnRails.configuration.server_bundle_js_file).to eq("server.js")
      expect(ReactOnRails.configuration.prerender).to be(false)
    end

    it "changes the configuration of the gem, such as setting the prerender option to true" do
      ReactOnRails.configure do |config|
        config.server_bundle_js_file = "something.js"
        config.prerender = true
        config.random_dom_id = false
      end

      expect(ReactOnRails.configuration.server_bundle_js_file).to eq("something.js")
      expect(ReactOnRails.configuration.prerender).to be(true)
      expect(ReactOnRails.configuration.random_dom_id).to be(false)
    end

    it "calls raise_missing_components_subdirectory if auto_load_bundle = true & components_subdirectory is not set" do
      expect do
        ReactOnRails.configure do |config|
          config.auto_load_bundle = true
        end
      end.to raise_error(ReactOnRails::Error, /components_subdirectory is not configured/)
    end

    it "checks that autobundling requirements are met if configuration options for autobundling are set" do
      allow(ReactOnRails::PackerUtils).to receive_messages(using_packer?: true,
                                                           shakapacker_version_requirement_met?: true,
                                                           nested_entries?: true)

      ReactOnRails.configure do |config|
        config.auto_load_bundle = true
        config.components_subdirectory = "something"
      end

      expect(ReactOnRails::PackerUtils).to have_received(:using_packer?).thrice
      expect(ReactOnRails::PackerUtils).to have_received(:shakapacker_version_requirement_met?)
      expect(ReactOnRails::PackerUtils).to have_received(:nested_entries?)
    end

    it "has a default configuration of the gem" do
      # rubocop:disable Lint/EmptyBlock
      ReactOnRails.configure do |_config|
      end
      # rubocop:enable Lint/EmptyBlock

      expect(ReactOnRails.configuration.random_dom_id).to be(true)
    end
  end
end

# rubocop:enable Metrics/ModuleLength
