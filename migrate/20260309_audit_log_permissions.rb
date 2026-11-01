# frozen_string_literal: true

Sequel.migration do
  up do
    # ttzzzzzzzz021g0pj0avd1t100
    from(:action_type).insert(id: "ffffffff-ff00-835a-802d-202b6d0e8200", name: "Project:auditlog")

    # Add to Project:all
    from(:applied_action_tag).insert(tag_id: "ffffffff-ff00-834a-87ff-ff82d2028210", action_id: "ffffffff-ff00-835a-802d-202b6d0e8200")
  end

  down do
    # Skip archiving, archived_record may lack partition for current month
    run "ALTER TABLE applied_action_tag DISABLE TRIGGER archived_record_insert"
    from(:applied_action_tag).where(action_id: "ffffffff-ff00-835a-802d-202b6d0e8200").delete
    run "ALTER TABLE applied_action_tag ENABLE TRIGGER archived_record_insert"
    from(:action_type).where(id: "ffffffff-ff00-835a-802d-202b6d0e8200").delete
  end
end
