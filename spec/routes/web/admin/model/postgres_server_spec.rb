# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe CloverAdmin, "PostgresServer" do
  include AdminModelSpecHelper

  before do
    project = Project.create(name: "test-project")
    resource = create_postgres_resource(project:, location_id: Location::HETZNER_FSN1_ID)
    @instance = create_postgres_server(resource:)
    admin_account_setup_and_login
  end

  it "displays the PostgresServer instance page correctly" do
    expect(PostgresServer).to receive(:victoria_metrics_client).and_return(nil)

    click_link "PostgresServer"
    expect(page.status_code).to eq 200
    expect(page.title).to eq "Ubicloud Admin - PostgresServer - Browse"

    click_link @instance.admin_label
    expect(page.status_code).to eq 200
    expect(page.title).to eq "Ubicloud Admin - PostgresServer #{@instance.ubid}"
  end

  it "renders charts when metrics are available" do
    tsdb_client = instance_double(VictoriaMetrics::Client)
    expect(PostgresServer).to receive(:victoria_metrics_client).and_return(tsdb_client)
    expect(tsdb_client).to receive(:query_range).twice.and_return([{"labels" => {}, "values" => [[Time.now.to_i, "5"]]}])

    visit "/model/PostgresServer/#{@instance.ubid}"
    expect(page.status_code).to eq 200
    expect(page.body).to include("<svg")
    expect(page.body).to include("steelblue")
  end
end
