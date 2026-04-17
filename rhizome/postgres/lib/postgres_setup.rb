# frozen_string_literal: true

require_relative "../../common/lib/util"
require "logger"

class PostgresSetup
  # Per-service GOMEMLIMIT targets, sum kept under go_services.slice MemoryHigh=2G
  GO_SERVICES = {
    "prometheus" => "1024MiB",
    "wal-g" => "384MiB",
    "postgres_exporter" => "256MiB",
    "node_exporter" => "256MiB",
  }.freeze

  def initialize(version)
    @version = version
  end

  def install_packages
    # Check if the packages exist in the cache, if so, install them.
    if File.exist?("/var/cache/postgresql-packages/#{@version}")
      r "sudo install-postgresql-packages #{@version}"
    end
  end

  def configure_memory_overcommit(strict: false)
    if strict
      total_mem_kb = File.read("/proc/meminfo").match(/MemTotal:\s+(\d+)/)[1].to_i
      overcommit_kbytes = (total_mem_kb * 0.8 + 2 * 1048576).round
      safe_write_to_file("/etc/sysctl.d/99-overcommit.conf", "vm.overcommit_memory=2\nvm.overcommit_kbytes=#{overcommit_kbytes}\n")
    else
      r "sudo rm -f /etc/sysctl.d/99-overcommit.conf"
    end

    r "sudo sysctl --system"
  end

  def configure_service_slice
    safe_write_to_file("/etc/systemd/system/go_services.slice", <<~SLICE)
      [Slice]
      MemoryHigh=2G
      MemoryMax=2560M
    SLICE
    GO_SERVICES.each do |svc, gomemlimit|
      r "mkdir -p /etc/systemd/system/#{svc}.service.d"
      safe_write_to_file("/etc/systemd/system/#{svc}.service.d/override.conf", <<~OVERRIDE)
        [Service]
        Slice=go_services.slice
        Environment=GOMEMLIMIT=#{gomemlimit}
      OVERRIDE
    end
    r "systemctl daemon-reload"
    # Apply cap so without restarting. Slice= and GOMEMLIMIT are load-time directives,
    # so only restart services not yet in slice.
    r "systemctl set-property go_services.slice MemoryHigh=2G MemoryMax=2560M"
    GO_SERVICES.each_key do |svc|
      current_slice = r("systemctl show #{svc}.service -p Slice --value").strip
      next if current_slice == "go_services.slice"
      r "systemctl try-restart #{svc}.service", expect: [0, 1]
    end
  end

  def setup_data_directory
    r "chown postgres /dat"

    # Below commands are required for idempotency
    r "rm -rf /dat/#{@version}"
    r "rm -rf /etc/postgresql/#{@version}"

    r "echo \"data_directory = '/dat/#{@version}/data'\" | sudo tee /etc/postgresql-common/createcluster.d/data-dir.conf"
  end

  def create_cluster
    r "pg_createcluster #{@version} main --port=5432 --locale=C.UTF8"
  end
end
