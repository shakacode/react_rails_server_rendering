# frozen_string_literal: true

require "equivalent-xml"

RSpec::Matchers.define :script_tag_be_included do |expected|
  opts = {}
  match do |actual|
    Nokogiri::HTML.fragment(actual).css("script").map do |script|
      EquivalentXml.equivalent?(Nokogiri::HTML.fragment(script.to_s.delete(" \t\r\n")),
                                Nokogiri::HTML.fragment(expected.delete(" \t\r\n")),
                                opts)
    end.include?(true)
  end

  chain :ignoring_content_of do |paths|
    opts[:ignore_content] = paths
  end

  chain :ignoring_attr_values do |*attrs|
    opts[:ignore_attr_values] = attrs
  end

  should_message = lambda do |actual|
    ["expected:", expected.to_s, "got:", actual.to_s].join("\n")
  end

  should_not_message = lambda do |actual|
    ["expected:", actual.to_s, "not to be equivalent to:", expected.to_s].join("\n")
  end

  if respond_to?(:failure_message_when_negated)
    failure_message(&should_message)
    failure_message_when_negated(&should_not_message)
  else
    failure_message_for_should(&should_message)
    failure_message_for_should_not(&should_not_message)
  end

  diffable
end
