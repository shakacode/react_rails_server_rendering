# frozen_string_literal: true

require_relative "spec_helper"

module ReactOnRails
  describe PackerUtils do
    describe ".shakapacker_version_requirement_met?" do
      minimum_version = [6, 5, 3]

      it "returns false when version is lower than minimum_version" do
        allow(described_class).to receive(:shakapacker_version).and_return("6.5.0")

        expect(described_class.shakapacker_version_requirement_met?(minimum_version)).to be(false)

        allow(described_class).to receive(:shakapacker_version).and_return("6.4.7")
        expect(described_class.shakapacker_version_requirement_met?(minimum_version)).to be(false)

        allow(described_class).to receive(:shakapacker_version).and_return("5.7.7")
        expect(described_class.shakapacker_version_requirement_met?(minimum_version)).to be(false)
      end

      it "returns true when version is equal to minimum_version" do
        allow(described_class).to receive(:shakapacker_version).and_return("6.5.3")
        expect(described_class.shakapacker_version_requirement_met?(minimum_version)).to be(true)
      end

      it "returns true when version is greater than minimum_version" do
        allow(described_class).to receive(:shakapacker_version).and_return("6.6.0")
        expect(described_class.shakapacker_version_requirement_met?(minimum_version)).to be(true)

        allow(described_class).to receive(:shakapacker_version).and_return("6.5.4")
        expect(described_class.shakapacker_version_requirement_met?(minimum_version)).to be(true)

        allow(described_class).to receive(:shakapacker_version).and_return("7.7.7")
        expect(described_class.shakapacker_version_requirement_met?(minimum_version)).to be(true)
      end
    end

    describe ".asset_uri_from_packer" do
      let(:asset_name) { "test-asset.js" }
      let(:public_output_path) { "/path/to/public/webpack/dev" }

      context "when dev server is running" do
        before do
          allow(described_class.packer).to receive(:dev_server).and_return(
            instance_double(
              (ReactOnRails::PackerUtils.packer)::DevServer,
              running?: true,
              protocol: "http",
              host_with_port: "localhost:3035"
            )
          )

          allow(described_class.packer).to receive_message_chain("config.public_output_path")
            .and_return(Pathname.new(public_output_path))
          allow(described_class.packer).to receive_message_chain("config.public_path")
            .and_return(Pathname.new("/path/to/public"))
        end

        it "returns asset URL with dev server path" do
          expected_url = "http://localhost:3035/webpack/dev/test-asset.js"
          expect(described_class.asset_uri_from_packer(asset_name)).to eq(expected_url)
        end
      end

      context "when dev server is not running" do
        before do
          allow(described_class.packer).to receive_message_chain("dev_server.running?").and_return(false)
          allow(described_class.packer).to receive_message_chain("config.public_output_path")
            .and_return(Pathname.new(public_output_path))
        end

        it "returns file path to the asset" do
          expected_path = File.join(public_output_path, asset_name)
          expect(described_class.asset_uri_from_packer(asset_name)).to eq(expected_path)
        end
      end
    end
  end
end
