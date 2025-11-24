# frozen_string_literal: true

if (suite = ENV.delete("COVERAGE"))
  require "simplecov"

  SimpleCov.start do
    enable_coverage :branch
    minimum_coverage line: 100, branch: 100
    minimum_coverage_by_file line: 100, branch: 100

    command_name "#{suite}#{ENV["TEST_ENV_NUMBER"]}"

    # Support filtering to specific files via COVERAGE_FILES env var
    # Usage: COVERAGE=1 COVERAGE_FILES="prog/postgres/file1.rb,lib/file2.rb" bundle exec rspec
    if (coverage_files = ENV["COVERAGE_FILES"])
      target_files = coverage_files.split(",").map(&:strip)
      add_filter do |file|
        !target_files.any? { |f| file.filename.include?(f) }
      end
    elsif suite == "rhizome"
      require "pathname"
      LOCKED_FILES = ["rhizome/kubernetes/lib/ubi_cni.rb"].map do |file|
        Pathname.new(File.expand_path("..", __dir__)).join(file).to_s
      end

      add_filter do |file|
        !LOCKED_FILES.include?(file.filename)
      end
    else
      add_filter do |file|
        path = file.filename.delete_prefix(File.dirname(__dir__))
        path.match?(/\A\/(rhizome|kubernetes|migrate|spec|var|vendor|(db|model|loader|\.env)\.rb)/)
      end
    end

    add_group("Missing") { |src| src.covered_percent < 100 }
    add_group("Covered") { |src| src.covered_percent == 100 }

    track_files "**/*.rb"
  end
end
