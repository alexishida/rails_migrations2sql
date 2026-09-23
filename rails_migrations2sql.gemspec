# frozen_string_literal: true

require_relative "lib/rails_migrations2sql/version"

Gem::Specification.new do |spec|
  spec.name = "rails_migrations2sql"
  spec.version = RailsMigrations2sql::VERSION
  spec.authors = ["Alex Ishida"]

  spec.summary = "Compile Rails migrations into SQL for DBA execution."
  spec.description = "Compiles Rails 8 migrations into one SQL file per migration and target, with application statements and version registration. Supports PostgreSQL, MySQL, MariaDB, Oracle and Microsoft SQL Server without applying migrations to a database or evaluating rollback."
  spec.license = "MIT"
  spec.homepage = "https://github.com/alexishida/rails_migrations2sql"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "README.md", "LICENSE.txt", "Rakefile"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 8.0", "< 9.0"
  spec.add_dependency "activesupport", ">= 8.0", "< 9.0"
  spec.add_dependency "railties", ">= 8.0", "< 9.0"
end
