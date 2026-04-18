# frozen_string_literal: true

class Prog::Postgres::UnarchivePostgresResource < Prog::Base
  def self.assemble(postgres_resource_id)
    if postgres_resource_id.is_a?(String) && postgres_resource_id.bytesize == 26
      postgres_resource_id = UBID.to_uuid(postgres_resource_id) || fail("Invalid UBID: #{postgres_resource_id}")
    end

    Strand.create(
      prog: "Postgres::UnarchivePostgresResource",
      label: "start",
      stack: [{"postgres_resource_id" => postgres_resource_id}]
    )
  end

  def postgres_resource_id
    @postgres_resource_id ||= frame.fetch("postgres_resource_id")
  end

  label def start
    archived = ArchivedRecord.find_by_id(postgres_resource_id, model_name: "PostgresResource", days: 15)
    fail "No archived PostgresResource for id #{postgres_resource_id}" unless archived

    last_n_days = Sequel::CURRENT_TIMESTAMP - Sequel.cast("15 days", :interval)
    archived_server = DB[:archived_record]
      .where(model_name: "PostgresServer")
      .where { archived_at > last_n_days }
      .where(Sequel.pg_jsonb_op(:model_values).get_text("resource_id") => postgres_resource_id)
      .where(Sequel.pg_jsonb_op(:model_values).get_text("is_representative") => "true")
      .first
    fail "No archived representative PostgresServer for id #{postgres_resource_id}" unless archived_server

    timeline_id = archived_server[:model_values]["timeline_id"]
    timeline = PostgresTimeline[timeline_id]
    fail "Original timeline #{timeline_id} no longer exists" unless timeline

    # An orphaned timeline stops accepting WAL at destroy time. The last WAL
    # upload's mtime is slightly after its newest transaction (wal-g uploads
    # once a segment rotates), so back off 60s to land reliably inside WAL
    # data — otherwise postgres FATALs with "recovery ended before configured
    # recovery target was reached".
    latest_wal = timeline.latest_wal_upload_time
    fail "Original timeline #{timeline_id} has no WAL archives" unless latest_wal
    restore_target = latest_wal - 60

    v = archived[:model_values]
    strand = Prog::Postgres::PostgresResourceNexus.assemble(
      project_id: v["project_id"],
      location_id: v["location_id"],
      name: v["name"],
      target_vm_size: v["target_vm_size"],
      target_storage_size_gib: v["target_storage_size_gib"],
      target_version: v["target_version"],
      flavor: v["flavor"],
      ha_type: v["ha_type"],
      tags: v["tags"] || [],
      user_config: v["user_config"] || {},
      pgbouncer_user_config: v["pgbouncer_user_config"] || {},
      restore_from_timeline_id: timeline_id,
      restore_target:
    )

    # Orphan-timeline restore generates a fresh superuser_password, but WAL
    # replay leaves the on-disk role with the old password. `configure` only
    # hops to update_superuser_password while initial_provisioning is set,
    # and wait_recovery_completion clears it before the promoted server
    # revisits configure. Set the semaphore so `wait` pushes the new password.
    strand.subject.representative_server.incr_update_superuser_password

    pop({"msg" => "postgres resource restored", "resource_id" => strand.id})
  end
end
