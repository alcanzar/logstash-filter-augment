# encoding: utf-8
require_relative '../spec_helper'
require "logstash/filters/augment"

describe LogStash::Filters::Augment do
  describe "static config" do
    config <<-CONFIG
    filter {
      augment {
        field => "status"
        dictionary => {
            "200" => {
              "color" => "green"
              "message" => "OK"
            }
            "404" => {
              "color" => "red"
              "message" => "Missing"
            }
        }
      }
    }
    CONFIG
    sample("status" => "200") do
      insist { subject.get("color")} == "green"
      insist { subject.get("message")} == "OK"
    end
  end
  describe "static config with defaults" do
    config <<-CONFIG
    filter {
      augment {
        field => "status"
        dictionary => {
            "200" => {
              "color" => "green"
              "message" => "OK"
            }
            "404" => {
              "color" => "red"
              "message" => "Missing"
            }
          }
          augment_default => {
            "color" => "orange"
            "message" => "not found"
          }
      }
    }
    CONFIG
    sample("status" => "201") do
      insist { subject.get("color")} == "orange"
      insist { subject.get("message")} == "not found"
    end
  end
  describe "invalid config because dictionary isn't right" do
    config <<-CONFIG
    filter {
      augment {
        field => "status"
        dictionary => {
            "200" => "OK"
            "404" => "Bogus"
          }
      }
    }
    CONFIG
    sample("status" => "200") do
      expect { subject }.to raise_exception LogStash::ConfigurationError
    end
  end
  describe "simple csv file with header ignored" do
    filename = File.join(File.dirname(__FILE__), "..", "fixtures", "test-with-headers.csv")
    config <<-CONFIG
    filter {
      augment {
        field => "status"
        dictionary_path => '#{filename}'
        csv_header => ["status","color","message"]
        csv_first_line => "ignore"
      }
    }
    CONFIG
    sample("status" => "200") do
      insist { subject.get("color")} == "green"
      insist { subject.get("message")} == "ok"
    end
  end
  describe "simple csv file with header, but not ignored" do
    filename = File.join(File.dirname(__FILE__), "..", "fixtures", "test-with-headers.csv")
    config <<-CONFIG
    filter {
      augment {
        field => "status"
        dictionary_path => '#{filename}'
      }
    }
    CONFIG
    sample("status" => "200") do
      insist { subject.get("color")} == "green"
      insist { subject.get("message")} == "ok"
    end
  end
  describe "simple csv file with ignore_fields set" do
    filename = File.join(File.dirname(__FILE__), "..", "fixtures", "test-with-headers.csv")
    config <<-CONFIG
    filter {
      augment {
        field => "status"
        dictionary_path => '#{filename}'
        ignore_fields => ["color"]
      }
    }
    CONFIG
    sample("status" => "200") do
      insist { subject.get("color")} == nil
      insist { subject.get("message")} == "ok"
    end
  end
  describe "json-hash" do
    filename = File.join(File.dirname(__FILE__), "..", "fixtures", "json-hash.json")
    config <<-CONFIG
    filter {
      augment {
        field => "status"
        dictionary_path => '#{filename}'
      }
    }
    CONFIG
    sample("status" => "200") do
      insist { subject.get("color")} == "green"
      insist { subject.get("message")} == "ok"
    end
  end
  describe "json-array no json_key" do
    filename = File.join(File.dirname(__FILE__), "..", "fixtures", "json-array.json")
    config <<-CONFIG
    filter {
      augment {
        field => "status"
        dictionary_path => '#{filename}'
      }
    }
    CONFIG
    sample("status" => "404") do
      expect { subject }.to raise_exception RuntimeError
    end
  end
  describe "json-array with json_key" do
    filename = File.join(File.dirname(__FILE__), "..", "fixtures", "json-array.json")
    config <<-CONFIG
    filter {
      augment {
        field => "status"
        dictionary_path => '#{filename}'
        json_key => "code"
      }
    }
    CONFIG
    sample("status" => "404") do
      insist { subject.get("color")} == "red"
      insist { subject.get("message")} == "not found"
    end
  end
  describe "json-array with integer key" do
    filename = File.join(File.dirname(__FILE__), "..", "fixtures", "json-array-int-key.json")
    config <<-CONFIG
    filter {
      augment {
        field => "status"
        dictionary_path => '#{filename}'
        json_key => "code"
      }
    }
    CONFIG
    sample("status" => "404") do
      insist { subject.get("color")} == "red"
      insist { subject.get("message")} == "not found"
    end
  end
end
