# frozen_string_literal: true

require_relative "spec_helper"
require ReactOnRails::PackerUtils.packer_type

# rubocop:disable Metrics/ModuleLength, Metrics/BlockLength
module ReactOnRails
  RSpec.describe Utils do
    # Github Actions already run rspec tests two times, once with shakapacker and once with webpacker.
    # If rspec tests are run locally, we want to test both packers.
    # If rspec tests are run in CI, we want to test the packer specified in the CI_PACKER_VERSION environment variable.
    # Check script/convert and .github/workflows/rspec-package-specs.yml for more details.
    packers_to_test = if ENV["CI_PACKER_VERSION"] == "old"
                        ["webpacker"]
                      elsif ENV["CI_PACKER_VERSION"] == "new"
                        ["shakapacker"]
                      else
                        %w[shakapacker webpacker]
                      end

    shared_context "with packer enabled" do
      before do
        allow(ReactOnRails).to receive_message_chain(:configuration, :generated_assets_dir)
          .and_return("")
        allow(ReactOnRails::PackerUtils.packer).to receive_message_chain("dev_server.running?")
          .and_return(false)
        allow(ReactOnRails::PackerUtils.packer).to receive_message_chain("config.public_output_path")
          .and_return(packer_public_output_path)
      end

      it "uses packer" do
        expect(ReactOnRails::PackerUtils.using_packer?).to be(true)
      end
    end

    shared_context "with shakapacker enabled" do
      include_context "with packer enabled"

      # We don't need to mock anything here because the shakapacker gem is already installed and will be used by default
      it "uses shakapacker" do
        expect(ReactOnRails::PackerUtils.using_webpacker_const?).to be(false)
        expect(ReactOnRails::PackerUtils.using_shakapacker_const?).to be(true)
        expect(ReactOnRails::PackerUtils.packer_type).to eq("shakapacker")
        expect(ReactOnRails::PackerUtils.packer).to eq(::Shakapacker)
      end
    end

    shared_context "with webpacker enabled" do
      include_context "with packer enabled"

      it "uses webpacker" do
        expect(ReactOnRails::PackerUtils.using_shakapacker_const?).to be(false)
        expect(ReactOnRails::PackerUtils.using_webpacker_const?).to be(true)
        expect(ReactOnRails::PackerUtils.packer_type).to eq("webpacker")
        expect(ReactOnRails::PackerUtils.packer).to be_a(::Webpacker)
      end
    end

    shared_context "without packer enabled" do
      before do
        allow(ReactOnRails).to receive_message_chain(:configuration, :generated_assets_dir)
          .and_return("public/webpack/dev")
        allow(described_class).to receive(:gem_available?).with("shakapacker").and_return(false)
        allow(described_class).to receive(:gem_available?).with("webpacker").and_return(false)
      end

      it "does not use packer" do
        expect(ReactOnRails::PackerUtils.using_packer?).to be(false)
        expect(ReactOnRails::PackerUtils.packer_type).to be_nil
        expect(ReactOnRails::PackerUtils.packer).to be_nil
      end
    end

    def mock_bundle_in_manifest(bundle_name, hashed_bundle)
      mock_manifest = instance_double(Object.const_get(ReactOnRails::PackerUtils.packer_type.capitalize)::Manifest)
      allow(mock_manifest).to receive(:lookup!)
        .with(bundle_name)
        .and_return(hashed_bundle)

      allow(ReactOnRails::PackerUtils.packer).to receive(:manifest).and_return(mock_manifest)
    end

    def mock_missing_manifest_entry(bundle_name)
      allow(ReactOnRails::PackerUtils.packer).to receive_message_chain("manifest.lookup!")
        .with(bundle_name)
        .and_raise(Object.const_get(
          ReactOnRails::PackerUtils.packer_type.capitalize
        )::Manifest::MissingEntryError)
    end

    def random_bundle_name
      "webpack-bundle-#{SecureRandom.hex(4)}.js"
    end

    # If bundle names are not provided, random unique names will be used for each bundle.
    # This ensures that if server_bundle and rsc_bundle are accidentally swapped in the code,
    # the tests will fail since each bundle has a distinct random name that won't match if used incorrectly.
    def mock_bundle_configs(server_bundle_name: random_bundle_name, rsc_bundle_name: random_bundle_name)
      allow(ReactOnRails).to receive_message_chain("configuration.server_bundle_js_file")
        .and_return(server_bundle_name)
      allow(ReactOnRails).to receive_message_chain("configuration.rsc_bundle_js_file")
        .and_return(rsc_bundle_name)
    end

    def mock_dev_server_running
      allow(ReactOnRails::PackerUtils.packer).to receive_message_chain("dev_server.running?")
        .and_return(true)
      allow(ReactOnRails::PackerUtils.packer).to receive_message_chain("dev_server.protocol")
        .and_return("http")
      allow(ReactOnRails::PackerUtils.packer).to receive_message_chain("dev_server.host_with_port")
        .and_return("localhost:3035")
    end

    context "when server_bundle_path cleared" do
      before do
        allow(Rails).to receive(:root).and_return(File.expand_path("."))
        described_class.instance_variable_set(:@server_bundle_path, nil)
        described_class.instance_variable_set(:@rsc_bundle_path, nil)
        ReactOnRails::PackerUtils.instance_variables.each do |instance_variable|
          ReactOnRails::PackerUtils.remove_instance_variable(instance_variable)
        end
      end

      after do
        described_class.instance_variable_set(:@server_bundle_path, nil)
        described_class.instance_variable_set(:@rsc_bundle_path, nil)
      end

      describe ".bundle_js_file_path" do
        subject do
          described_class.bundle_js_file_path("webpack-bundle.js")
        end

        packers_to_test.each do |packer_type|
          context "with #{packer_type} enabled", packer_type.to_sym do
            include_context "with #{packer_type} enabled"

            let(:packer_public_output_path) do
              File.expand_path(File.join(Rails.root, "public/webpack/dev"))
            end

            context "when file in manifest", :shakapacker do
              before do
                mock_bundle_in_manifest("webpack-bundle.js", "/webpack/dev/webpack-bundle-0123456789abcdef.js")

                mock_bundle_configs(server_bundle_name: "server-bundle.js")
              end

              it { is_expected.to eq("#{packer_public_output_path}/webpack-bundle-0123456789abcdef.js") }
            end

            context "with manifest.json" do
              subject do
                described_class.bundle_js_file_path("manifest.json")
              end

              it { is_expected.to eq("#{packer_public_output_path}/manifest.json") }
            end
          end
        end

        context "without a packer enabled" do
          include_context "without packer enabled"

          it { is_expected.to eq(File.expand_path(File.join(Rails.root, "public/webpack/dev/webpack-bundle.js"))) }
        end
      end

      describe ".source_path_is_not_defined_and_custom_node_modules?" do
        it "returns false if node_modules is blank" do
          allow(ReactOnRails).to receive_message_chain("configuration.node_modules_location")
            .and_return("")
          allow(ReactOnRails::PackerUtils).to receive_message_chain("packer.config.send").with(:data)
                                                                                         .and_return({})

          expect(described_class.using_packer_source_path_is_not_defined_and_custom_node_modules?).to be(false)
        end

        it "returns false if source_path is defined in the config/webpacker.yml and node_modules defined" do
          allow(ReactOnRails).to receive_message_chain("configuration.node_modules_location")
            .and_return("client")
          allow(ReactOnRails::PackerUtils).to receive_message_chain("packer.config.send")
            .with(:data).and_return(source_path: "client/app")

          expect(described_class.using_packer_source_path_is_not_defined_and_custom_node_modules?).to be(false)
        end

        it "returns true if node_modules is not blank and the source_path is not defined in config/webpacker.yml" do
          allow(ReactOnRails).to receive_message_chain("configuration.node_modules_location")
            .and_return("node_modules")
          allow(ReactOnRails::PackerUtils).to receive_message_chain("packer.config.send").with(:data)
                                                                                         .and_return({})

          expect(described_class.using_packer_source_path_is_not_defined_and_custom_node_modules?).to be(true)
        end
      end

      packers_to_test.each do |packer_type|
        describe ".server_bundle_js_file_path with #{packer_type} enabled" do
          let(:packer_public_output_path) { Pathname.new("public/webpack/development") }

          include_context "with #{packer_type} enabled"

          context "with server file not in manifest", packer_type.to_sym do
            it "returns the unhashed server path" do
              server_bundle_name = "server-bundle.js"
              mock_bundle_configs(server_bundle_name: server_bundle_name)
              mock_missing_manifest_entry(server_bundle_name)

              path = described_class.server_bundle_js_file_path

              expect(path).to end_with("public/webpack/development/#{server_bundle_name}")
            end
          end

          context "with server file in the manifest, used for client", packer_type.to_sym do
            it "returns the correct path hashed server path" do
              Packer = ReactOnRails::PackerUtils.packer # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
              mock_bundle_configs(server_bundle_name: "webpack-bundle.js")
              allow(ReactOnRails).to receive_message_chain("configuration.same_bundle_for_client_and_server")
                .and_return(true)
              mock_bundle_in_manifest("webpack-bundle.js", "webpack/development/webpack-bundle-123456.js")
              allow(Packer).to receive_message_chain("dev_server.running?")
                .and_return(false)

              path = described_class.server_bundle_js_file_path
              expect(path).to end_with("public/webpack/development/webpack-bundle-123456.js")
              expect(path).to start_with("/")
            end

            context "with webpack-dev-server running, and same file used for server and client" do
              it "returns the correct path hashed server path" do
                mock_bundle_configs(server_bundle_name: "webpack-bundle.js")
                allow(ReactOnRails).to receive_message_chain("configuration.same_bundle_for_client_and_server")
                  .and_return(true)
                mock_dev_server_running
                mock_bundle_in_manifest("webpack-bundle.js", "/webpack/development/webpack-bundle-123456.js")

                path = described_class.server_bundle_js_file_path

                expect(path).to eq("http://localhost:3035/webpack/development/webpack-bundle-123456.js")
              end
            end
          end

          context "with dev-server running, and server file in the manifest, and separate client/server files",
                  packer_type.to_sym do
            it "returns the correct path hashed server path" do
              mock_bundle_configs(server_bundle_name: "server-bundle.js")
              allow(ReactOnRails).to receive_message_chain("configuration.same_bundle_for_client_and_server")
                .and_return(false)
              mock_bundle_in_manifest("server-bundle.js", "webpack/development/server-bundle-123456.js")
              mock_dev_server_running

              path = described_class.server_bundle_js_file_path

              expect(path).to end_with("/public/webpack/development/server-bundle-123456.js")
            end
          end
        end

        describe ".rsc_bundle_js_file_path with #{packer_type} enabled" do
          let(:packer_public_output_path) { Pathname.new("public/webpack/development") }

          include_context "with #{packer_type} enabled"

          context "with server file not in manifest", packer_type.to_sym do
            it "returns the unhashed server path" do
              server_bundle_name = "rsc-bundle.js"
              mock_bundle_configs(rsc_bundle_name: server_bundle_name)
              mock_missing_manifest_entry(server_bundle_name)

              path = described_class.rsc_bundle_js_file_path

              expect(path).to end_with("public/webpack/development/#{server_bundle_name}")
            end
          end

          context "with server file in the manifest, used for client", packer_type.to_sym do
            it "returns the correct path hashed server path" do
              Packer = ReactOnRails::PackerUtils.packer # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
              mock_bundle_configs(rsc_bundle_name: "webpack-bundle.js")
              allow(ReactOnRails).to receive_message_chain("configuration.same_bundle_for_client_and_server")
                .and_return(true)
              mock_bundle_in_manifest("webpack-bundle.js", "webpack/development/webpack-bundle-123456.js")
              allow(Packer).to receive_message_chain("dev_server.running?")
                .and_return(false)

              path = described_class.rsc_bundle_js_file_path
              expect(path).to end_with("public/webpack/development/webpack-bundle-123456.js")
              expect(path).to start_with("/")
            end

            context "with webpack-dev-server running, and same file used for server and client" do
              it "returns the correct path hashed server path" do
                mock_bundle_configs(rsc_bundle_name: "webpack-bundle.js")
                allow(ReactOnRails).to receive_message_chain("configuration.same_bundle_for_client_and_server")
                  .and_return(true)
                mock_dev_server_running
                mock_bundle_in_manifest("webpack-bundle.js", "/webpack/development/webpack-bundle-123456.js")

                path = described_class.rsc_bundle_js_file_path

                expect(path).to eq("http://localhost:3035/webpack/development/webpack-bundle-123456.js")
              end
            end
          end

          context "with dev-server running, and server file in the manifest, and separate client/server files",
                  packer_type.to_sym do
            it "returns the correct path hashed server path" do
              mock_bundle_configs(rsc_bundle_name: "rsc-bundle.js")
              allow(ReactOnRails).to receive_message_chain("configuration.same_bundle_for_client_and_server")
                .and_return(false)
              mock_bundle_in_manifest("rsc-bundle.js", "webpack/development/server-bundle-123456.js")
              mock_dev_server_running

              path = described_class.rsc_bundle_js_file_path

              expect(path).to end_with("/public/webpack/development/server-bundle-123456.js")
            end
          end
        end
      end

      describe ".wrap_message" do
        subject(:stripped_heredoc) do
          <<-MSG.strip_heredoc
          Something to wrap
          with 2 lines
          MSG
        end

        let(:expected) do
          msg = <<-MSG.strip_heredoc
          ================================================================================
          Something to wrap
          with 2 lines
          ================================================================================
          MSG
          Rainbow(msg).red
        end

        it "outputs the correct text" do
          expect(described_class.wrap_message(stripped_heredoc)).to eq(expected)
        end
      end

      describe ".truthy_presence" do
        context "with non-empty string" do
          subject(:simple_string) { "foobar" }

          it "returns subject (same value as presence) for a non-empty string" do
            expect(described_class.truthy_presence(simple_string)).to eq(simple_string.presence)

            # Blank strings are nil for presence
            expect(described_class.truthy_presence(simple_string)).to eq(simple_string)
          end
        end

        context "with empty string" do
          it "returns \"\" for an empty string" do
            expect(described_class.truthy_presence("")).to eq("")
          end
        end

        context "with nil object" do
          it "returns nil (same value as presence)" do
            expect(described_class.truthy_presence(nil)).to eq(nil.presence)

            # Blank strings are nil for presence
            expect(described_class.truthy_presence(nil)).to be_nil
          end
        end

        context "with pathname pointing to empty dir (obj.empty? is true)" do
          subject(:empty_dir) { Pathname.new(Dir.mktmpdir) }

          it "returns Pathname object" do
            # Blank strings are nil for presence
            expect(described_class.truthy_presence(empty_dir)).to eq(empty_dir)
          end
        end

        context "with pathname pointing to empty file" do
          subject(:empty_file) do
            File.basename(Tempfile.new("tempfile",
                                       empty_dir))
          end

          let(:empty_dir) { Pathname.new(Dir.mktmpdir) }

          it "returns Pathname object" do
            expect(described_class.truthy_presence(empty_file)).to eq(empty_file)
          end
        end
      end

      describe ".rails_version_less_than" do
        subject { described_class.rails_version_less_than("4") }

        describe ".rails_version_less_than" do
          before { described_class.instance_variable_set :@rails_version_less_than, nil }

          context "with Rails 3" do
            before { allow(Rails).to receive(:version).and_return("3") }

            it { is_expected.to be(true) }
          end

          context "with Rails 3.2" do
            before { allow(Rails).to receive(:version).and_return("3.2") }

            it { is_expected.to be(true) }
          end

          context "with Rails 4" do
            before { allow(Rails).to receive(:version).and_return("4") }

            it { is_expected.to be(false) }
          end

          context "with Rails 4.2" do
            before { allow(Rails).to receive(:version).and_return("4.2") }

            it { is_expected.to be(false) }
          end

          context "with Rails 10.0" do
            before { allow(Rails).to receive(:version).and_return("10.0") }

            it { is_expected.to be(false) }
          end

          context "when called twice" do
            before do
              allow(Rails).to receive(:version).and_return("4.2")
            end

            it "memoizes the result" do
              2.times { described_class.rails_version_less_than("4") }

              expect(Rails).to have_received(:version).once
            end
          end
        end
      end

      describe ".smart_trim" do
        it "trims smartly" do
          s = "1234567890"

          expect(described_class.smart_trim(s, -1)).to eq("1234567890")
          expect(described_class.smart_trim(s, 0)).to eq("1234567890")
          expect(described_class.smart_trim(s, 1)).to eq("1#{Utils::TRUNCATION_FILLER}")
          expect(described_class.smart_trim(s, 2)).to eq("1#{Utils::TRUNCATION_FILLER}0")
          expect(described_class.smart_trim(s, 3)).to eq("1#{Utils::TRUNCATION_FILLER}90")
          expect(described_class.smart_trim(s, 4)).to eq("12#{Utils::TRUNCATION_FILLER}90")
          expect(described_class.smart_trim(s, 5)).to eq("12#{Utils::TRUNCATION_FILLER}890")
          expect(described_class.smart_trim(s, 6)).to eq("123#{Utils::TRUNCATION_FILLER}890")
          expect(described_class.smart_trim(s, 7)).to eq("123#{Utils::TRUNCATION_FILLER}7890")
          expect(described_class.smart_trim(s, 8)).to eq("1234#{Utils::TRUNCATION_FILLER}7890")
          expect(described_class.smart_trim(s, 9)).to eq("1234#{Utils::TRUNCATION_FILLER}67890")
          expect(described_class.smart_trim(s, 10)).to eq("1234567890")
          expect(described_class.smart_trim(s, 11)).to eq("1234567890")
        end

        it "trims handles a hash" do
          s = { a: "1234567890" }

          expect(described_class.smart_trim(s, 9)).to eq(
            "{:a=#{Utils::TRUNCATION_FILLER}890\"}"
          )
        end
      end

      describe ".react_on_rails_pro?" do
        subject { described_class.react_on_rails_pro? }

        it { is_expected.to(be(false)) }
      end

      describe ".react_on_rails_pro_version?" do
        subject { described_class.react_on_rails_pro_version }

        it { is_expected.to eq("") }
      end

      describe ".gem_available?" do
        it "calls Gem.loaded_specs" do
          expect(Gem).to receive(:loaded_specs)
          described_class.gem_available?("nonexistent_gem")
        end
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/BlockLength
