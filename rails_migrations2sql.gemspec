# frozen_string_literal: true

require_relative "lib/rails_migrations2sql/version"

Gem::Specification.new do |spec|
  spec.name = "rails_migrations2sql"
  spec.version = RailsMigrations2sql::VERSION
  spec.authors = ["Alex Ishida"]

  spec.summary = "Compile Rails migrations into DBA-ready SQL without running them."
  spec.description = "Compiles Rails 8 migrations offline into DBA-ready SQL packages, with up, down, register, unregister and manifest files for PostgreSQL, MySQL, MariaDB, Oracle and Microsoft SQL Server. Migrations are never applied and no database connection is required."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "README.md", "LICENSE.txt", "Rakefile"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 8.0", "< 9.0"
  spec.add_dependency "activesupport", ">= 8.0", "< 9.0"
  spec.add_dependency "railties", ">= 8.0", "< 9.0"
end
