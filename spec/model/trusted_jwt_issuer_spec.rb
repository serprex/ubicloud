# frozen_string_literal: true

require_relative "spec_helper"
require "jwt"

RSpec.describe TrustedJwtIssuer do
  let(:project) { Project.create(name: "test-project") }
  let(:account) { Account.create(email: "svc@example.com", status_id: 2) }
  let(:rsa_key) { Clec::Cert.rsa_2048_key }

  let(:issuer) do
    described_class.create(
      project_id: project.id,
      account_id: account.id,
      name: "test-issuer",
      issuer: "https://jwks.example.com",
      jwks_uri: "https://jwks.example.com/.well-known/jwks.json"
    )
  end

  def stub_jwks(uri, key: rsa_key, kid: "k1")
    jwk = JWT::JWK.new(key, kid:)
    stub_request(:get, uri).to_return(body: {keys: [jwk.export]}.to_json)
  end

  it "decodes JWT via JWKS URI" do
    stub_jwks(issuer.jwks_uri)
    token = JWT.encode({"iss" => issuer.issuer, "data" => "test"}, rsa_key, "RS256", {kid: "k1"})
    payload = issuer.decode_jwt(token)
    expect(payload["data"]).to eq("test")
  end

  it "caches JWKS and invalidates on kid miss" do
    stub = stub_jwks(issuer.jwks_uri)
    token = JWT.encode({"iss" => issuer.issuer}, rsa_key, "RS256", {kid: "k1"})

    issuer.decode_jwt(token)
    issuer.decode_jwt(token)
    # Only fetched once due to caching
    expect(stub).to have_been_requested.once

    # Decode with unknown kid triggers invalidation + re-fetch
    token2 = JWT.encode({"iss" => issuer.issuer}, rsa_key, "RS256", {kid: "k2"})
    expect { issuer.decode_jwt(token2) }.to raise_error(JWT::DecodeError)
    # Initial fetch + invalidation re-fetch
    expect(stub).to have_been_requested.twice
  end

  it "is valid subject tag member for its project" do
    expect(SubjectTag.valid_member?(project.id, issuer)).to be(true)
  end

  it "is not valid subject tag member for another project" do
    other_project = Project.create(name: "other")
    expect(SubjectTag.valid_member?(other_project.id, issuer)).to be(false)
  end

  it "cleans up ACEs and tag memberships on destroy" do
    tag = SubjectTag.create(project_id: project.id, name: "test-tag")
    tag.add_member(issuer.id)
    AccessControlEntry.create(project_id: project.id, subject_id: issuer.id)

    expect(DB[:applied_subject_tag].where(subject_id: issuer.id).count).to eq(1)
    expect(AccessControlEntry.where(subject_id: issuer.id).count).to eq(1)

    issuer.destroy

    expect(DB[:applied_subject_tag].where(subject_id: issuer.id).count).to eq(0)
    expect(AccessControlEntry.where(subject_id: issuer.id).count).to eq(0)
  end
end
