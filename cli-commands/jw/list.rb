# frozen_string_literal: true

UbiCli.on("jw", "list") do
  desc "List trusted JWT issuers"

  key = :jwt_issuer_list

  options("ubi jw list [options]", key:) do
    on("-N", "--no-headers", "do not show headers")
  end

  run do |opts|
    opts = opts[key]
    items = sdk.trusted_jwt_issuer.list
    response(format_rows(%i[id name issuer jwks_uri], items, headers: opts[:"no-headers"] != false))
  end
end
