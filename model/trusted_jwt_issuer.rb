# frozen_string_literal: true

require_relative "../model"

class TrustedJwtIssuer < Sequel::Model
  many_to_one :project, read_only: true
  many_to_one :account, read_only: true

  plugin ResourceMethods

  def parsed_public_key
    OpenSSL::PKey.read(public_key)
  end
end

# Table: trusted_jwt_issuer
# Columns:
#  id         | uuid | PRIMARY KEY
#  project_id | uuid | NOT NULL
#  account_id | uuid | NOT NULL
#  name       | text | NOT NULL
#  issuer     | text | NOT NULL
#  public_key | text | NOT NULL
# Indexes:
#  trusted_jwt_issuer_pkey                      | PRIMARY KEY btree (id)
#  trusted_jwt_issuer_project_id_issuer_index   | UNIQUE btree (project_id, issuer)
# Foreign key constraints:
#  trusted_jwt_issuer_project_id_fkey | (project_id) REFERENCES project(id)
#  trusted_jwt_issuer_account_id_fkey | (account_id) REFERENCES accounts(id)
