# frozen_string_literal: true

require "excon"
require_relative "../model"

class TrustedJwtIssuer < Sequel::Model
  plugin ResourceMethods
  include SubjectTag::Cleanup

  def decode_jwt(token)
    JWT.decode(token, nil, true, algorithms: ["RS256"], iss: issuer, verify_iss: true, jwks: jwks_loader)[0]
  end

  private

  def jwks_loader
    lambda do |options|
      @jwks = nil if options[:invalidate]
      @jwks ||= JSON.parse(Excon.get(jwks_uri, expects: [200]).body)
    end
  end
end

# Table: trusted_jwt_issuer
# Columns:
#  id         | uuid | PRIMARY KEY
#  project_id | uuid | NOT NULL
#  account_id | uuid | NOT NULL
#  name       | text | NOT NULL
#  issuer     | text | NOT NULL
#  jwks_uri   | text | NOT NULL
# Indexes:
#  trusted_jwt_issuer_pkey                      | PRIMARY KEY btree (id)
#  trusted_jwt_issuer_project_id_issuer_index   | UNIQUE btree (project_id, issuer)
# Foreign key constraints:
#  trusted_jwt_issuer_project_id_fkey | (project_id) REFERENCES project(id)
#  trusted_jwt_issuer_account_id_fkey | (account_id) REFERENCES accounts(id)
