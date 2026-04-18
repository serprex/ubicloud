# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Prog::Postgres::UnarchivePostgresResource do
  subject(:nx) { described_class.new(st) }

  let(:project) { Project.create(name: "test-project") }
  let(:location_id) { Location::HETZNER_FSN1_ID }
  let(:postgres_resource) { create_postgres_resource(project:, location_id:) }
  let(:postgres_server) { create_postgres_server(resource: postgres_resource) }
  let(:st) {
    Strand.create(
      prog: "Postgres::UnarchivePostgresResource",
      label: "start",
      stack: [{"postgres_resource_id" => postgres_resource.id}]
    )
  }

  describe ".assemble" do
    it "creates strand with postgres_resource_id in stack" do
      strand = described_class.assemble("00000000-0000-0000-0000-000000000001")
      expect(strand.prog).to eq("Postgres::UnarchivePostgresResource")
      expect(strand.label).to eq("start")
      expect(strand.stack.first["postgres_resource_id"]).to eq("00000000-0000-0000-0000-000000000001")
    end

    it "accepts a UBID and converts to UUID" do
      uuid = postgres_resource.id
      ubid = postgres_resource.ubid
      strand = described_class.assemble(ubid)
      expect(strand.stack.first["postgres_resource_id"]).to eq(uuid)
    end

    it "rejects malformed UBIDs" do
      expect { described_class.assemble("u" * 26) }.to raise_error(RuntimeError, /Invalid UBID/)
    end
  end

  describe "#start" do
    it "fails if archived PostgresResource not found" do
      id = postgres_resource.id
      postgres_resource.destroy
      ArchivedRecord.where(Sequel.pg_jsonb_op(:model_values).get_text("id") => id).delete(force: true)
      expect { nx.start }.to raise_error(RuntimeError, "No archived PostgresResource for id #{id}")
    end

    it "fails if archived representative server not found" do
      postgres_server
      id = postgres_resource.id
      postgres_resource.destroy
      DB[:archived_record].where(model_name: "PostgresServer").delete(force: true)
      expect { nx.start }.to raise_error(RuntimeError, "No archived representative PostgresServer for id #{id}")
    end

    it "fails if original timeline no longer exists" do
      postgres_server
      timeline = postgres_server.timeline
      postgres_resource.destroy
      postgres_server.destroy
      timeline.destroy
      expect { nx.start }.to raise_error(RuntimeError, /Original timeline .* no longer exists/)
    end

    it "fails if original timeline has no WAL archives" do
      postgres_server
      postgres_resource.destroy
      postgres_server.destroy
      allow_any_instance_of(PostgresTimeline).to receive(:latest_wal_upload_time).and_return(nil)
      expect { nx.start }.to raise_error(RuntimeError, /has no WAL archives/)
    end

    it "assembles new resource fetching from the original timeline" do
      postgres_server
      original_name = postgres_resource.name
      original_project_id = postgres_resource.project_id
      original_location_id = postgres_resource.location_id
      original_timeline_id = postgres_server.timeline_id
      wal_time = Time.now - 300

      postgres_resource.destroy
      postgres_server.destroy
      allow_any_instance_of(PostgresTimeline).to receive(:latest_wal_upload_time).and_return(wal_time)

      new_server = instance_double(PostgresServer)
      expect(new_server).to receive(:incr_update_superuser_password)
      new_subject = instance_double(PostgresResource, representative_server: new_server)
      new_strand = instance_double(Strand, id: "00000000-0000-0000-0000-0000000000aa", subject: new_subject)
      expect(Prog::Postgres::PostgresResourceNexus).to receive(:assemble).with(
        hash_including(
          project_id: original_project_id,
          location_id: original_location_id,
          name: original_name,
          restore_from_timeline_id: original_timeline_id,
          restore_target: wal_time - 60
        )
      ).and_return(new_strand)

      expect { nx.start }.to exit({"msg" => "postgres resource restored", "resource_id" => new_strand.id})
    end
  end
end
