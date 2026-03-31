# frozen_string_literal: true

RSpec.describe Docsmith::Events::Notifier do
  let(:doc)     { instance_double("Docsmith::Document") }
  let(:version) { instance_double("Docsmith::DocumentVersion") }
  let(:author)  { instance_double("User") }

  describe ".instrument" do
    it "fires the registered hook synchronously" do
      received = nil
      Docsmith.configure { |c| c.on(:version_created) { |e| received = e } }

      described_class.instrument(:version_created,
        record: doc, document: doc, version: version, author: author)

      expect(received).to be_a(Docsmith::Events::Event)
      expect(received.version).to eq(version)
    end

    it "publishes to ActiveSupport::Notifications" do
      payload_received = nil
      ActiveSupport::Notifications.subscribe("version_created.docsmith") do |_name, _start, _finish, _id, payload|
        payload_received = payload
      end

      described_class.instrument(:version_created,
        record: doc, document: doc, version: version, author: author)

      expect(payload_received).not_to be_nil
    ensure
      ActiveSupport::Notifications.unsubscribe("version_created.docsmith")
    end

    it "returns the Event object" do
      event = described_class.instrument(:version_created,
        record: doc, document: doc, version: version, author: author)
      expect(event).to be_a(Docsmith::Events::Event)
    end
  end
end
