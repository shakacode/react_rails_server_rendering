# frozen_string_literal: true

require "rails_helper"
require "support/script_tag_utils"

Packer = Object.const_get(ReactOnRails::PackerUtils.packer_type.capitalize)

class PlainReactOnRailsHelper
  include ReactOnRailsHelper
  include ActionView::Helpers::TagHelper
end

# rubocop:disable Metrics/BlockLength
describe ReactOnRailsHelper do
  include Packer::Helper
  before do
    allow(self).to receive(:request) {
      Struct.new("Request", :original_url, :env)
      Struct::Request.new(
        "http://foobar.com/development",
        { "HTTP_ACCEPT_LANGUAGE" => "en" }
      )
    }
  end

  let(:hash) do
    {
      hello: "world",
      free: "of charge",
      x: "</script><script>alert('foo')</script>"
    }
  end

  let(:json_string_sanitized) do
    '{"hello":"world","free":"of charge","x":"\\u003c/script\\u003e\\u003cscrip' \
      "t\\u003ealert('foo')\\u003c/script\\u003e\"}"
  end

  let(:json_string_unsanitized) do
    "{\"hello\":\"world\",\"free\":\"of charge\",\"x\":\"</script><script>alert('foo')</script>\"}"
  end

  describe "#load_pack_for_generated_component" do
    let(:render_options) do
      ReactOnRails::ReactComponent::RenderOptions.new(react_component_name: "component_name",
                                                      options: {})
    end

    it "appends js/css pack tag" do
      allow(helper).to receive(:append_javascript_pack_tag)
      allow(helper).to receive(:append_stylesheet_pack_tag)
      expect { helper.load_pack_for_generated_component("component_name", render_options) }.not_to raise_error
      expect(helper).to have_received(:append_javascript_pack_tag).with("generated/component_name", { defer: true })
      expect(helper).to have_received(:append_stylesheet_pack_tag).with("generated/component_name")
    end

    it "throws an error in development if generated component isn't found" do
      allow(Rails.env).to receive(:development?).and_return(true)
      expect { helper.load_pack_for_generated_component("nonexisting_component", render_options) }
        .to raise_error(ReactOnRails::Error, /the generated component entrypoint/)
    end
  end

  describe "#json_safe_and_pretty(hash_or_string)" do
    it "raises an error if not hash nor string nor nil passed" do
      expect { helper.json_safe_and_pretty(false) }.to raise_error(ReactOnRails::Error)
    end

    it "returns empty json when an empty Hash" do
      escaped_json = helper.json_safe_and_pretty({})
      expect(escaped_json).to eq("{}")
    end

    it "returns empty json when an empty HashWithIndifferentAccess" do
      escaped_json = helper.json_safe_and_pretty(HashWithIndifferentAccess.new)
      expect(escaped_json).to eq("{}")
    end

    it "returns empty json when nil" do
      escaped_json = helper.json_safe_and_pretty(nil)
      expect(escaped_json).to eq("{}")
    end

    it "converts a hash to escaped JSON" do
      escaped_json = helper.json_safe_and_pretty(hash)
      expect(escaped_json).to eq(json_string_sanitized)
    end

    it "converts a string to escaped JSON" do
      escaped_json = helper.json_safe_and_pretty(json_string_unsanitized)
      expect(escaped_json).to eq(json_string_sanitized)
    end

    context "when json is an instance of ActiveSupport::SafeBuffer" do
      it "converts to escaped JSON" do
        json = ActiveSupport::SafeBuffer.new(
          "{\"hello\":\"world\"}"
        )

        result = helper.json_safe_and_pretty(json)

        expect(result).to eq('{"hello":"world"}')
      end
    end
  end

  describe "#sanitized_props_string(props)" do
    it "converts a hash to JSON and escapes </script>" do
      sanitized = helper.sanitized_props_string(hash)
      expect(sanitized).to eq(json_string_sanitized)
    end

    it "leaves a string alone that does not contain xss tags" do
      sanitized = helper.sanitized_props_string(json_string_sanitized)
      expect(sanitized).to eq(json_string_sanitized)
    end

    it "fixes a string alone that contain xss tags" do
      sanitized = helper.sanitized_props_string(json_string_unsanitized)
      expect(sanitized).to eq(json_string_sanitized)
    end
  end

  describe "#react_component" do
    subject(:react_app) { react_component("App", props: props) }

    before { allow(SecureRandom).to receive(:uuid).and_return(0, 1, 2, 3) }

    let(:props) do
      { name: "My Test Name" }
    end

    let(:react_component_random_id_div) do
      '<div id="App-react-component-0"></div>'
    end

    let(:react_component_div) do
      '<div id="App-react-component"></div>'
    end

    let(:id) { "App-react-component-0" }

    let(:react_definition_script) do
      <<-SCRIPT.strip_heredoc
        <script type="application/json" id="js-react-on-rails-context">{"railsEnv":"test","inMailer":false,"i18nLocale":"en","i18nDefaultLocale":"en","rorVersion":"14.1.0","rorPro":false,"href":"http://foobar.com/development","location":"/development","scheme":"http","host":"foobar.com","port":null,"pathname":"/development","search":null,"httpAcceptLanguage":"en","somethingUseful":null,"serverSide":false}</script>
        <div id="App-react-component"></div>
        <script type="application/json" class="js-react-on-rails-component" id="js-react-on-rails-component-App-react-component" data-component-name="App" data-dom-id="App-react-component" data-store-dependencies="[]">{"name":"My Test Name"}</script>
      SCRIPT
    end

    let(:react_definition_script_no_params) do
      <<-SCRIPT.strip_heredoc
        <script type="application/json" id="js-react-on-rails-context">{"railsEnv":"test","inMailer":false,"i18nLocale":"en","i18nDefaultLocale":"en","rorVersion":"14.1.0","rorPro":false,"href":"http://foobar.com/development","location":"/development","scheme":"http","host":"foobar.com","port":null,"pathname":"/development","search":null,"httpAcceptLanguage":"en","somethingUseful":null,"serverSide":false}</script>
        <div id="App-react-component"></div>
        <script type="application/json" class="js-react-on-rails-component" id="js-react-on-rails-component-App-react-component" data-component-name="App" data-dom-id="App-react-component" data-store-dependencies="[]">{}</script>
      SCRIPT
    end

    context "with json string props" do
      subject { react_component("App", props: json_props) }

      let(:json_props) do
        "{\"hello\":\"world\",\"free\":\"of charge\",\"x\":\"</script><script>alert('foo')</script>\"}"
      end

      let(:json_props_sanitized) do
        '{"hello":"world","free":"of charge","x":"\\u003c/script\\u003e\\u003cscrip' \
          "t\\u003ealert('foo')\\u003c/script\\u003e\"}"
      end

      it { is_expected.to include json_props_sanitized }
    end

    describe "API with component name only (no props or other options)" do
      subject(:react_app) { react_component("App") }

      it { is_expected.to be_an_instance_of ActiveSupport::SafeBuffer }
      it { is_expected.to include react_component_div }

      it {
        expect(expect(react_app).target).to script_tag_be_included(react_definition_script_no_params)
      }
    end

    it { expect(self).to respond_to :react_component }

    it { is_expected.to be_an_instance_of ActiveSupport::SafeBuffer }
    it { is_expected.to start_with "<script" }
    it { is_expected.to match %r{</script>\s*$} }
    it { is_expected.to include react_component_div }

    it {
      expect(expect(react_app).target).to script_tag_be_included(react_definition_script)
    }

    context "with 'random_dom_id' option set to false" do
      subject(:react_app) { react_component("App", props: props, random_dom_id: false) }

      let(:react_definition_script) do
        <<-SCRIPT.strip_heredoc
          <script type="application/json" id="js-react-on-rails-context">{"railsEnv":"test","inMailer":false,"i18nLocale":"en","i18nDefaultLocale":"en","rorVersion":"14.1.0","rorPro":false,"href":"http://foobar.com/development","location":"/development","scheme":"http","host":"foobar.com","port":null,"pathname":"/development","search":null,"httpAcceptLanguage":"en","somethingUseful":null,"serverSide":false}</script>
          <div id="App-react-component"></div>
          <script type="application/json" class="js-react-on-rails-component" id="js-react-on-rails-component-App-react-component" data-component-name="App" data-dom-id="App-react-component" data-store-dependencies="[]">{"name":"My Test Name"}</script>
        SCRIPT
      end

      it { is_expected.to include '<div id="App-react-component"></div>' }
      it { expect(expect(react_app).target).to script_tag_be_included(react_definition_script) }
    end

    context "with 'random_dom_id' option set to true" do
      subject(:react_app) { react_component("App", props: props, random_dom_id: true) }

      let(:react_definition_script) do
        <<-SCRIPT.strip_heredoc
          <script type="application/json" id="js-react-on-rails-context">{"railsEnv":"test","inMailer":false,"i18nLocale":"en","i18nDefaultLocale":"en","rorVersion":"14.1.0","rorPro":false,"href":"http://foobar.com/development","location":"/development","scheme":"http","host":"foobar.com","port":null,"pathname":"/development","search":null,"httpAcceptLanguage":"en","somethingUseful":null,"serverSide":false}</script>
          <div id="App-react-component-0"></div>
          <script type="application/json" class="js-react-on-rails-component" id="js-react-on-rails-component-App-react-component-0" data-component-name="App" data-dom-id="App-react-component-0" data-store-dependencies="[]">{"name":"My Test Name"}</script>
        SCRIPT
      end

      it { is_expected.to include '<div id="App-react-component-0"></div>' }
      it { expect(expect(react_app).target).to script_tag_be_included(react_definition_script) }
    end

    context "with 'random_dom_id' global" do
      subject(:react_app) { react_component("App", props: props) }

      around do |example|
        ReactOnRails.configure { |config| config.random_dom_id = false }
        example.run
        ReactOnRails.configure { |config| config.random_dom_id = true }
      end

      let(:react_definition_script) do
        <<-SCRIPT.strip_heredoc
          <script type="application/json" id="js-react-on-rails-context">{"railsEnv":"test","inMailer":false,"i18nLocale":"en","i18nDefaultLocale":"en","rorVersion":"14.1.0","rorPro":false,"href":"http://foobar.com/development","location":"/development","scheme":"http","host":"foobar.com","port":null,"pathname":"/development","search":null,"httpAcceptLanguage":"en","somethingUseful":null,"serverSide":false}</script>
          <div id="App-react-component"></div>
          <script type="application/json" class="js-react-on-rails-component" id="js-react-on-rails-component-App-react-component" data-component-name="App" data-dom-id="App-react-component" data-store-dependencies="[]">{"name":"My Test Name"}</script>
        SCRIPT
      end

      it { is_expected.to include '<div id="App-react-component"></div>' }
      it { expect(expect(react_app).target).to script_tag_be_included(react_definition_script) }
    end

    context "with 'id' option" do
      subject(:react_app) { react_component("App", props: props, id: id) }

      let(:id) { "shaka_div" }

      let(:react_definition_script) do
        <<-SCRIPT.strip_heredoc
          <script type="application/json" id="js-react-on-rails-context">{"railsEnv":"test","inMailer":false,"i18nLocale":"en","i18nDefaultLocale":"en","rorVersion":"14.1.0","rorPro":false,"href":"http://foobar.com/development","location":"/development","scheme":"http","host":"foobar.com","port":null,"pathname":"/development","search":null,"httpAcceptLanguage":"en","somethingUseful":null,"serverSide":false}</script>
          <div id="shaka_div"></div>
          <script type="application/json" class="js-react-on-rails-component" id="js-react-on-rails-component-shaka_div" data-component-name="App" data-dom-id="shaka_div" data-store-dependencies="[]">{"name":"My Test Name"}</script>
        SCRIPT
      end

      it { is_expected.to include id }
      it { is_expected.not_to include react_component_random_id_div }

      it {
        expect(expect(react_app).target).to script_tag_be_included(react_definition_script)
      }
    end

    context "with 'trace' == true" do
      it "adds the data-trace tag to the component_specification_tag" do
        result = react_component("App", trace: true)

        expect(result).to match(/data-trace="true"/)
      end
    end

    context "with 'trace' == false" do
      it "does not add the data-trace tag" do
        result = react_component("App", trace: false)

        expect(result).not_to match(/data-trace=/)
      end
    end

    context "with 'html_options' tag option" do
      subject { react_component("App", html_options: { tag: "span" }) }

      it { is_expected.to include '<span id="App-react-component-0"></span>' }
      it { is_expected.not_to include '<div id="App-react-component-0"></div>' }
    end

    context "without 'html_options' tag option" do
      subject { react_component("App") }

      it { is_expected.not_to include '<span id="App-react-component-0"></span>' }
      it { is_expected.to include '<div id="App-react-component-0"></div>' }
    end

    describe "'force_load' tag option" do
      let(:force_load_script) do
        %(
ReactOnRails.reactOnRailsComponentLoaded('App-react-component-0');
        ).html_safe
      end

      context "with 'force_load' == true" do
        subject { react_component("App", force_load: true) }

        it { is_expected.to include force_load_script }
      end

      context "without 'force_load' tag option" do
        subject { react_component("App") }

        it { is_expected.not_to include force_load_script }
      end
    end
  end

  describe "#redux_store" do
    subject(:store) { redux_store("reduxStore", props: props) }

    let(:props) do
      { name: "My Test Name" }
    end

    let(:react_store_script) do
      '<script type="application/json" data-js-react-on-rails-store="reduxStore">' \
        '{"name":"My Test Name"}' \
        "</script>"
    end

    it { expect(self).to respond_to :redux_store }

    it { is_expected.to be_an_instance_of ActiveSupport::SafeBuffer }
    it { is_expected.to start_with "<script" }
    it { is_expected.to end_with "</script>" }

    it {
      expect(expect(store).target).to script_tag_be_included(react_store_script)
    }
  end

  describe "#server_render_js", :js, type: :system do
    subject { server_render_js("ReactOnRails.getComponent('HelloString').component.world()") }

    let(:hello_world) do
      "Hello WORLD! Will this work?? YES! Time to visit Maui"
    end

    it { expect(self).to respond_to :react_component }

    it { is_expected.to be_an_instance_of ActiveSupport::SafeBuffer }
    it { is_expected.to eq hello_world }
  end

  describe "#rails_context" do
    around do |example|
      rendering_extension = ReactOnRails.configuration.rendering_extension
      ReactOnRails.configuration.rendering_extension = nil

      example.run

      ReactOnRails.configuration.rendering_extension = rendering_extension
    end

    it "does not throw an error if not in a view" do
      ob = PlainReactOnRailsHelper.new
      expect { ob.send(:rails_context, server_side: true) }.not_to raise_error
      expect { ob.send(:rails_context, server_side: false) }.not_to raise_error
    end
  end

  describe "#rails_context_if_not_already_rendered" do
    let(:helper) { PlainReactOnRailsHelper.new }

    before do
      allow(helper).to receive(:rails_context).and_return({ some: "context" })
    end

    it "returns a script tag with rails context when not already rendered" do
      result = helper.send(:rails_context_if_not_already_rendered)
      expect(result).to include('<script type="application/json" id="js-react-on-rails-context">')
      expect(result).to include('"some":"context"')
    end

    it "returns an empty string when already rendered" do
      helper.instance_variable_set(:@rendered_rails_context, true)
      result = helper.send(:rails_context_if_not_already_rendered)
      expect(result).to eq("")
    end

    it "calls rails_context with server_side: false" do
      helper.send(:rails_context_if_not_already_rendered)
      expect(helper).to have_received(:rails_context).with(server_side: false)
    end
  end
end
# rubocop:enable Metrics/BlockLength
