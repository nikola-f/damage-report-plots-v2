# frozen_string_literal: true

require "rails_helper"

RSpec.describe PollingWorker do
  let(:worker_class) do
    Class.new do
      include PollingWorker

      def self.perform_in(_interval); end

      def logger = Rails.logger
    end
  end
  let(:worker)   { worker_class.new }
  let(:key)      { "polling_worker_spec:lock" }
  let(:ttl)      { 60 }
  let(:interval) { 30 }
  let(:token)    { "test-token" }

  before do
    allow(SecureRandom).to receive(:uuid).and_return(token)
    allow(worker_class).to receive(:perform_in)
    allow(REDIS).to receive(:set).with(key, token, nx: true, ex: ttl).and_return("OK")
    allow(REDIS).to receive(:eval)
  end

  def with_lock(&block)
    worker.with_lock(key:, ttl:, interval:, &block)
  end

  context "when the lock is acquired" do
    it "stores a unique token under the lock key with the TTL" do
      with_lock { nil }

      expect(REDIS).to have_received(:set).with(key, token, nx: true, ex: ttl)
    end

    it "yields the block" do
      expect { |b| with_lock(&b) }.to yield_control
    end

    it "releases the lock only if it still holds this worker's token" do
      with_lock { nil }

      expect(REDIS).to have_received(:eval)
        .with(PollingWorker::RELEASE_LOCK_SCRIPT, keys: [key], argv: [token])
    end

    it "releases the lock even when the block raises" do
      expect { with_lock { raise "boom" } }.to raise_error("boom")

      expect(REDIS).to have_received(:eval)
        .with(PollingWorker::RELEASE_LOCK_SCRIPT, keys: [key], argv: [token])
    end

    it "reschedules itself after the interval" do
      with_lock { nil }

      expect(worker_class).to have_received(:perform_in).with(interval)
    end
  end

  context "when the lock is held by another worker" do
    before do
      allow(REDIS).to receive(:set).with(key, token, nx: true, ex: ttl).and_return(nil)
    end

    it "does not yield the block" do
      expect { |b| with_lock(&b) }.not_to yield_control
    end

    it "does not touch the lock" do
      with_lock { nil }

      expect(REDIS).not_to have_received(:eval)
    end

    it "reschedules itself after the interval" do
      with_lock { nil }

      expect(worker_class).to have_received(:perform_in).with(interval)
    end
  end

  describe "RELEASE_LOCK_SCRIPT" do
    it "deletes the key only when the stored token matches" do
      # Guards the compare-and-delete semantics: a worker that overran the TTL
      # must not delete the lock a newer worker has since acquired.
      expect(PollingWorker::RELEASE_LOCK_SCRIPT)
        .to include('redis.call("get", KEYS[1]) == ARGV[1]')
    end
  end
end
