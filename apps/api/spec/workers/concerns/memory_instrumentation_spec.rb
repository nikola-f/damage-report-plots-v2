# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemoryInstrumentation do
  let(:instrumented) do
    Class.new do
      include MemoryInstrumentation
    end.new
  end

  describe "#current_rss_mb" do
    it "returns the resident set size in MB as a positive number" do
      expect(instrumented.current_rss_mb).to be_a(Float).and be > 0
    end

    it "returns nil when /proc/self/status is unavailable" do
      allow(File).to receive(:exist?).with(MemoryInstrumentation::PROC_STATUS).and_return(false)

      expect(instrumented.current_rss_mb).to be_nil
    end
  end

  describe "#peak_rss_mb" do
    it "returns the peak RSS (high-water mark) in MB as a positive number" do
      expect(instrumented.peak_rss_mb).to be_a(Float).and be > 0
    end

    it "is greater than or equal to the current RSS" do
      expect(instrumented.peak_rss_mb).to be >= instrumented.current_rss_mb
    end
  end
end
