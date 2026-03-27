# frozen_string_literal: true

require_relative "spec_helper"
require "jwt"

RSpec.describe TrustedJwtIssuer do
  let(:project) { Project.create(name: "test-project") }
  let(:account) { Account.create(email: "svc@example.com", status_id: 2) }
  let(:rsa_key) { Clec::Cert.rsa_2048_key }

  it "decodes JWT via JWKS URI" do
    jwk = JWT::JWK.new(rsa_key, kid: "k1")
    jwks_response = {keys: [jwk.export]}.to_json

    issuer = described_class.create(
      project_id: project.id,
      account_id: account.id,
      name: "jwks-test",
      issuer: "https://jwks.example.com",
      jwks_uri: "https://jwks.example.com/.well-known/jwks.json"
    )

    stub_request(:get, issuer.jwks_uri).to_return(body: jwks_response)

    token = JWT.encode({"iss" => issuer.issuer, "data" => "jwks"}, rsa_key, "RS256", {kid: "k1"})
    payload = issuer.decode_jwt(token)
    expect(payload["data"]).to eq("jwks")
  end
end
