# frozen_string_literal: true

require "rails_helper"

# rubocop:disable Metrics/ModuleLength
module ReactOnRails
  GENERATED_PACKS_CONSOLE_OUTPUT_REGEX = /Generated Packs:/

  # rubocop:disable Metrics/BlockLength
  describe PacksGenerator do
    let(:packer_source_path) { File.expand_path("./fixtures/automated_packs_generation", __dir__) }
    let(:packer_source_entry_path) { File.expand_path("./fixtures/automated_packs_generation/packs", __dir__) }
    let(:generated_directory) { File.expand_path("./fixtures/automated_packs_generation/packs/generated", __dir__) }
    let(:server_bundle_js_file) { "server-bundle.js" }
    let(:server_bundle_js_file_path) do
      File.expand_path("./fixtures/automated_packs_generation/packs/#{server_bundle_js_file}", __dir__)
    end
    let(:webpack_generated_files) { %w[manifest.json] }

    let(:old_server_bundle) { ReactOnRails.configuration.server_bundle_js_file }
    let(:old_subdirectory) { ReactOnRails.configuration.components_subdirectory }
    let(:old_auto_load_bundle) { ReactOnRails.configuration.auto_load_bundle }

    before do
      ReactOnRails.configuration.server_bundle_js_file = server_bundle_js_file
      ReactOnRails.configuration.components_subdirectory = "ror_components"
      ReactOnRails.configuration.webpack_generated_files = webpack_generated_files
      allow(ReactOnRails::PackerUtils).to receive_messages(
        manifest_exists?: true,
        nested_entries?: true,
        packer_source_entry_path: packer_source_entry_path
      )
      allow(ReactOnRails::Utils).to receive_messages(generated_assets_full_path: packer_source_entry_path,
                                                     server_bundle_js_file_path: server_bundle_js_file_path)
    end

    after do
      ReactOnRails.configuration.server_bundle_js_file = old_server_bundle
      ReactOnRails.configuration.components_subdirectory = old_subdirectory

      FileUtils.rm_rf "#{packer_source_entry_path}/generated"
      FileUtils.rm_rf generated_server_bundle_file_path
      File.truncate(server_bundle_js_file_path, 0)
    end

    context "when the generated server bundle is configured as ReactOnRails.configuration.server_bundle_js_file" do
      it "generates the server bundle within the source_entry_point" do
        FileUtils.mv(server_bundle_js_file_path, "./temp")
        FileUtils.rm_rf server_bundle_js_file_path
        ReactOnRails.configuration.make_generated_server_bundle_the_entrypoint = true
        described_class.instance.generate_packs_if_stale
        expect(File.exist?(server_bundle_js_file_path)).to equal(true)
        expect(File.exist?("#{Pathname(packer_source_entry_path).parent}/server-bundle-generated.js"))
          .to equal(false)
        FileUtils.mv("./temp", server_bundle_js_file_path)
        ReactOnRails.configuration.make_generated_server_bundle_the_entrypoint = false
      end
    end

    context "when component with common file only" do
      let(:component_name) { "ComponentWithCommonOnly" }
      let(:component_pack) { "#{generated_directory}/#{component_name}.js" }

      before do
        stub_packer_source_path(component_name: component_name,
                                packer_source_path: packer_source_path)
        described_class.instance.generate_packs_if_stale
      end

      it "creates generated pack directory" do
        expect(Pathname.new(generated_directory)).to be_directory
      end

      it "creates generated server bundle file" do
        expect(File.exist?(generated_server_bundle_file_path)).to equal(true)
      end

      it "creates pack for ComponentWithCommonOnly" do
        expect(File.exist?(component_pack)).to be(true)
      end

      it "generated pack for ComponentWithCommonOnly uses common file for pack" do
        pack_content = File.read(component_pack)

        expect(pack_content).to include("#{component_name}.jsx")
        expect(pack_content).not_to include("#{component_name}.client.jsx")
        expect(pack_content).not_to include("#{component_name}.server.jsx")
      end

      it "generated server bundle uses common file" do
        generated_server_bundle_content = File.read(generated_server_bundle_file_path)

        expect(generated_server_bundle_content).to include("#{component_name}.jsx")
        expect(generated_server_bundle_content).not_to include("#{component_name}.client.jsx")
        expect(generated_server_bundle_content).not_to include("#{component_name}.server.jsx")
      end
    end

    context "when component with client and common File" do
      let(:component_name) { "ComponentWithClientAndCommon" }
      let(:component_pack) { "#{generated_directory}/#{component_name}.js" }

      before do
        stub_packer_source_path(component_name: component_name,
                                packer_source_path: packer_source_path)
      end

      it "raises an error for definition override" do
        msg = <<~MSG
          **ERROR** ReactOnRails: client specific definition for Component '#{component_name}' overrides the \
          common definition. Please delete the common definition and have separate server and client files. For more \
          information, please see https://www.shakacode.com/react-on-rails/docs/guides/file-system-based-automated-bundle-generation.md
        MSG

        expect { described_class.instance.generate_packs_if_stale }.to raise_error(ReactOnRails::Error, msg)
      end
    end

    context "when component with server and common file" do
      let(:component_name) { "ComponentWithServerAndCommon" }
      let(:component_pack) { "#{generated_directory}/#{component_name}.js" }

      before do
        allow(ReactOnRails::PackerUtils).to receive(:packer_source_path)
          .and_return("#{packer_source_path}/components/#{component_name}")
      end

      it "raises an error for definition override" do
        msg = <<~MSG
          **ERROR** ReactOnRails: server specific definition for Component '#{component_name}' overrides the \
          common definition. Please delete the common definition and have separate server and client files. For more \
          information, please see https://www.shakacode.com/react-on-rails/docs/guides/file-system-based-automated-bundle-generation.md
        MSG

        expect { described_class.instance.generate_packs_if_stale }.to raise_error(ReactOnRails::Error, msg)
      end
    end

    context "when component with server, client and common file" do
      let(:component_name) { "ComponentWithCommonClientAndServer" }
      let(:component_pack) { "#{generated_directory}/#{component_name}.js" }

      before do
        stub_packer_source_path(component_name: component_name,
                                packer_source_path: packer_source_path)
      end

      it "raises an error for definition override" do
        msg =  /Please delete the common definition and have separate server and client files/
        expect { described_class.instance.generate_packs_if_stale }.to raise_error(ReactOnRails::Error, msg)
      end
    end

    context "when component with server only" do
      let(:component_name) { "ComponentWithServerOnly" }
      let(:component_pack) { "#{generated_directory}/#{component_name}.js" }

      before do
        stub_packer_source_path(component_name: component_name,
                                packer_source_path: packer_source_path)
      end

      it "raises missing client file error" do
        msg = <<~MSG
          **ERROR** ReactOnRails: Component '#{component_name}' is missing a client specific file. For more \
          information, please see https://www.shakacode.com/react-on-rails/docs/guides/file-system-based-automated-bundle-generation.md
        MSG

        expect { described_class.instance.generate_packs_if_stale }.to raise_error(ReactOnRails::Error, msg)
      end
    end

    context "when component with client only" do
      let(:component_name) { "ComponentWithClientOnly" }
      let(:component_pack) { "#{generated_directory}/#{component_name}.js" }

      before do
        stub_packer_source_path(component_name: component_name,
                                packer_source_path: packer_source_path)
        described_class.instance.generate_packs_if_stale
      end

      it "creates generated pack directory" do
        expect(Pathname.new(generated_directory)).to be_directory
      end

      it "creates generated server bundle file" do
        expect(File.exist?(generated_server_bundle_file_path)).to be(true)
      end

      it "creates pack for ComponentWithClientOnly" do
        expect(File.exist?(component_pack)).to be(true)
      end

      it "generated pack for ComponentWithClientOnly uses client file for pack" do
        pack_content = File.read(component_pack)

        expect(pack_content).to include("#{component_name}.client.jsx")
        expect(pack_content).not_to include("#{component_name}.jsx")
        expect(pack_content).not_to include("#{component_name}.server.jsx")
      end

      it "generated server bundle do not have ComponentWithClientOnly registered" do
        generated_server_bundle_content = File.read(generated_server_bundle_file_path)

        expect(generated_server_bundle_content).not_to include("#{component_name}.jsx")
        expect(generated_server_bundle_content).not_to include("#{component_name}.client.jsx")
        expect(generated_server_bundle_content).not_to include("#{component_name}.server.jsx")
      end
    end

    context "when pack generator is called" do
      let(:component_name) { "ComponentWithCommonOnly" }
      let(:component_pack) { "#{generated_directory}/#{component_name}.js" }

      before do
        stub_packer_source_path(component_name: component_name,
                                packer_source_path: packer_source_path)
        FileUtils.mkdir_p(generated_directory)
        File.write(component_pack, "wat")
        File.write(generated_server_bundle_file_path, "wat")
      end

      after do
        FileUtils.rm_rf generated_directory
        FileUtils.rm generated_server_bundle_file_path
      end

      it "does not generate packs if there are no new components or stale files" do
        expect do
          described_class.instance.generate_packs_if_stale
        end.not_to output(GENERATED_PACKS_CONSOLE_OUTPUT_REGEX).to_stdout
      end

      it "adds a single import statement to the server bundle" do
        test_string = "// import statement added by react_on_rails:generate_packs"
        same_instance = described_class.instance
        File.truncate(server_bundle_js_file_path, 0)
        same_instance.generate_packs_if_stale
        expect(File.read(server_bundle_js_file_path).scan(/(?=#{test_string})/).count).to equal(1)
        # the following expectation checks that an additional import statement is not added if one already exists
        same_instance.generate_packs_if_stale
        expect(File.read(server_bundle_js_file_path).scan(/(?=#{test_string})/).count).to equal(1)
      end

      it "generate packs if a new component is added" do
        create_new_component("NewComponent")

        expect do
          described_class.instance.generate_packs_if_stale
        end.to output(GENERATED_PACKS_CONSOLE_OUTPUT_REGEX).to_stdout
        FileUtils.rm "#{packer_source_path}/components/ComponentWithCommonOnly/ror_components/NewComponent.jsx"
      end

      it "generate packs if an old component is updated" do
        FileUtils.rm component_pack
        create_new_component(component_name)

        expect do
          described_class.instance.generate_packs_if_stale
        end.to output(GENERATED_PACKS_CONSOLE_OUTPUT_REGEX).to_stdout
      end

      def create_new_component(name)
        components_subdirectory = ReactOnRails.configuration.components_subdirectory
        path = "#{packer_source_path}/components/#{component_name}/#{components_subdirectory}/#{name}.jsx"

        File.write(path, "// Empty Test Component\n")
      end
    end

    context "when components subdirectory is not set & auto_load_bundle is false" do
      it "does not generate packs" do
        old_sub = old_subdirectory
        old_auto = old_auto_load_bundle
        ReactOnRails.configuration.components_subdirectory = nil
        ReactOnRails.configuration.auto_load_bundle = false
        expect do
          described_class.instance.generate_packs_if_stale
        end.not_to output(GENERATED_PACKS_CONSOLE_OUTPUT_REGEX).to_stdout
        ReactOnRails.configuration.components_subdirectory = old_sub
        ReactOnRails.configuration.auto_load_bundle = old_auto
      end
    end

    def generated_server_bundle_file_path
      described_class.instance.send(:generated_server_bundle_file_path)
    end

    def stub_packer_source_path(packer_source_path:, component_name:)
      allow(ReactOnRails::PackerUtils).to receive(:packer_source_path)
        .and_return("#{packer_source_path}/components/#{component_name}")
    end

    describe "#first_js_statement_in_code" do
      subject { described_class.instance.send(:first_js_statement_in_code, content) }

      context "with simple content" do
        let(:content) { "const x = 1;" }
        it { is_expected.to eq "const x = 1;" }
      end

      context "with single-line comments" do
        let(:content) do
          <<~JS
            // First comment
            // Second comment
            const x = 1;
            const y = 2;
          JS
        end
        it { is_expected.to eq "const x = 1;" }
      end

      context "with multi-line comments" do
        let(:content) do
          <<~JS
            /* This is a
               multiline comment */
            const x = 1;
          JS
        end
        it { is_expected.to eq "const x = 1;" }
      end

      context "with mixed comments" do
        let(:content) do
          <<~JS
            // Single line comment
            /* Multi-line
               comment */
            // Another single line
            const x = 1;
          JS
        end
        it { is_expected.to eq "const x = 1;" }
      end

      context "with mixed comments and whitespace" do
        let(:content) do
          <<~JS

            // First comment
              
            /*
              multiline comment
            */

                // comment with preceding whitespace

            // Another single line


            const x = 1;
          JS
        end
        it { is_expected.to eq "const x = 1;" }
      end

      context "with only comments" do
        let(:content) do
          <<~JS
            // Just a comment
            /* Another comment */
          JS
        end
        it { is_expected.to eq "" }
      end

      context "with comment at end of file" do
        let(:content) { "const x = 1;\n// Final comment" }
        it { is_expected.to eq "const x = 1;" }
      end

      context "with empty content" do
        let(:content) { "" }
        it { is_expected.to eq "" }
      end

      context "with only whitespace" do
        let(:content) { "   \n  \t  " }
        it { is_expected.to eq "" }
      end

      context "with statement containing comment-like strings" do
        let(:content) { 'const url = "http://example.com"; // Real comment' }
        # it returns the statement starting from non-space character until the next line even if it contains a comment
        it { is_expected.to eq 'const url = "http://example.com"; // Real comment' }
      end

      context "with unclosed multi-line comment" do
        let(:content) do
          <<~JS
            /* This comment
               never ends
            const x = 1;
          JS
        end
        it { is_expected.to eq "" }
      end

      context "with nested comments" do
        let(:content) do
          <<~JS
            // /* This is still a single line comment */
            const x = 1;
          JS
        end
        it { is_expected.to eq "const x = 1;" }
      end

      context "with one line comment with no space after //" do
        let(:content) { "//const x = 1;" }
        it { is_expected.to eq "" }
      end

      context "with one line comment with no new line after it" do
        let(:content) { "// const x = 1" }
        it { is_expected.to eq "" }
      end

      context "with string directive" do
        context "on top of the file" do
          let(:content) do
            <<~JS
              "use client";
              // const x = 1
              const b = 2;
            JS
          end
          it { is_expected.to eq '"use client";' }
        end
  
        context "on top of the file and one line comment" do
          let(:content) { '"use client"; // const x = 1' }
          it { is_expected.to eq '"use client"; // const x = 1' }
        end
  
        context "after some one-line comments" do
          let(:content) do
            <<~JS
              // First comment
              // Second comment
              "use client";
            JS
          end
          it { is_expected.to eq '"use client";' }
        end

        context "after some multi-line comments" do
          let(:content) do
            <<~JS
              /* First comment */
              /*
                multiline comment
              */
              "use client";
            JS
          end
          it { is_expected.to eq '"use client";' }
        end

        context "after some mixed comments" do
          let(:content) do
            <<~JS
              // First comment
              /*
                multiline comment
              */
              "use client";
            JS
          end
          it { is_expected.to eq '"use client";' }
        end

        context "after any non-comment code" do
          let(:content) do
            <<~JS
              // First comment
              const x = 1;
              "use client";
            JS
          end
          it { is_expected.to eq 'const x = 1;' }
        end
      end
    end

    describe "#is_client_entrypoint?", :focus do
      subject { described_class.instance.send(:is_client_entrypoint?, "dummy_path.js") }
      
      before do
        allow(File).to receive(:read).with("dummy_path.js").and_return(content)
      end

      context "when file has 'use client' directive" do
        context "with double quotes" do
          let(:content) { '"use client";' }
          it { is_expected.to be true }
        end

        context "with single quotes" do
          let(:content) { "'use client';" }
          it { is_expected.to be true }
        end

        context "without semicolon" do
          let(:content) { '"use client"' }
          it { is_expected.to be true }
        end

        context "with trailing whitespace" do
          let(:content) { '"use client"  ' }
          it { is_expected.to be true }
        end

        context "with comments before directive" do
          let(:content) do
            <<~JS
              // some comment
              /* multi-line
                 comment */
              "use client";
            JS
          end
          it { is_expected.to be true }
        end
      end

      context "when file does not have 'use client' directive" do
        context "with empty file" do
          let(:content) { "" }
          it { is_expected.to be false }
        end

        context "with regular JS code" do
          let(:content) { "const x = 1;" }
          it { is_expected.to be false }
        end

        context "with 'use client' in a comment" do
          let(:content) { "// 'use client'" }
          it { is_expected.to be false }
        end

        context "with 'use client' in middle of file" do
          let(:content) do
            <<~JS
              const x = 1;
              "use client";
            JS
          end
          it { is_expected.to be false }
        end

        context "with similar but incorrect directive" do
          let(:content) { 'use client;' } # without quotes
          it { is_expected.to be false }
        end
      end
    end
  end
  # rubocop:enable Metrics/BlockLength
end
# rubocop:enable Metrics/ModuleLength
