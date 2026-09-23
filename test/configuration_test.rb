# frozen_string_literal: true

require_relative "test_helper"
require "rails"
require "generators/rails_migrations2sql/install_generator"
require "tmpdir"

class ConfigurationTest < Minitest::Test
  def setup
    @previous_configurations = ActiveRecord::Base.configurations
    @previous_environment = Rails.env
    @previous_target = ENV.delete("RAILS_DBA_TARGET")
    @previous_database_url = ENV.delete("DATABASE_URL")
    Rails.env = "test"
    ActiveRecord::Base.configurations = {}
  end

  def teardown
    ActiveRecord::Base.configurations = @previous_configurations
    Rails.env = @previous_environment
    ENV["RAILS_DBA_TARGET"] = @previous_target
    ENV["DATABASE_URL"] = @previous_database_url
  end

  {
    "postgresql" => :postgresql,
    "mysql2" => :mysql,
    "trilogy" => :mysql,
    "mysql" => :mysql,
    "mariadb" => :mariadb,
    "oracle_enhanced" => :oracle,
    "oracle" => :oracle,
    "sqlserver" => :sqlserver
  }.each do |adapter, expected|
    define_method("test_detects_#{adapter}_without_a_database_connection") do
      set_adapter(adapter)
      RailsMigrations2sql::OfflineGuard.protect do
        configuration = RailsMigrations2sql::Configuration.new
        assert_equal expected, configuration.target
        configuration.validate!
      end
    end
  end

  def test_detects_the_current_environment
    ActiveRecord::Base.configurations = {
      "test" => { "adapter" => "postgresql" },
      "production" => { "adapter" => "oracle_enhanced" }
    }
    configuration = RailsMigrations2sql::Configuration.new
    assert_equal :postgresql, configuration.target
    Rails.env = "production"
    assert_equal :oracle, configuration.target
  end

  def test_primary_takes_precedence_over_other_databases
    ActiveRecord::Base.configurations = {
      "test" => {
        "queue" => { "adapter" => "sqlite3" },
        "primary" => { "adapter" => "sqlserver" }
      }
    }
    assert_equal :sqlserver, RailsMigrations2sql::Configuration.new.target
  end

  def test_without_primary_uses_first_database_enabled_for_tasks
    ActiveRecord::Base.configurations = {
      "test" => {
        "replica" => { "adapter" => "postgresql", "replica" => true },
        "application" => { "adapter" => "mysql2" }
      }
    }
    assert_equal :mysql, RailsMigrations2sql::Configuration.new.target
  end

  def test_uses_the_resolved_database_url
    ENV["DATABASE_URL"] = "postgresql://example.invalid/application"
    ActiveRecord::Base.configurations = { "test" => {} }
    RailsMigrations2sql::OfflineGuard.protect do
      assert_equal :postgresql, RailsMigrations2sql::Configuration.new.target
    end
  end

  def test_detection_is_deferred_until_rails_configuration_is_available
    configuration = RailsMigrations2sql::Configuration.new
    set_adapter("oracle_enhanced")
    assert_equal :oracle, configuration.target
  end

  def test_explicit_target_overrides_environment_and_environment_overrides_auto
    set_adapter("postgresql")
    ENV["RAILS_DBA_TARGET"] = "mariadb"
    configuration = RailsMigrations2sql::Configuration.new
    configuration.target = :auto
    assert_equal :mariadb, configuration.target
    configuration.target = :oracle
    assert_equal :oracle, configuration.target
  end

  def test_unsupported_adapter_reports_a_useful_error
    set_adapter("sqlite3")
    error = assert_raises(RailsMigrations2sql::ConfigurationError) { RailsMigrations2sql::Configuration.new.target }
    assert_includes error.message, "sqlite3"
    assert_includes error.message, "TARGET"
  end

  def test_missing_database_does_not_fall_back_to_postgresql
    error = assert_raises(RailsMigrations2sql::ConfigurationError) { RailsMigrations2sql::Configuration.new.target }
    assert_includes error.message, "No database configuration found for test"
  end

  def test_explicit_command_target_bypasses_unsupported_auto_detection
    set_adapter("sqlite3")
    Dir.mktmpdir("rails-migrations2sql-target") do |directory|
      configuration = RailsMigrations2sql::Configuration.new
      configuration.migrations_paths = [File.expand_path("fixtures/migrations", __dir__)]
      configuration.output_path = directory
      result = RailsMigrations2sql::Generator.new(configuration).generate(version: "20260923130000", target: :oracle)
      assert_equal [:oracle], result.targets
      assert File.file?(File.join(directory, "oracle/20260923130000_sql_export_create_articles.sql"))
    end
  end

  def test_generated_initializer_uses_auto_detection
    set_adapter("oracle_enhanced")
    previous = RailsMigrations2sql.configuration
    RailsMigrations2sql.instance_variable_set(:@configuration, RailsMigrations2sql::Configuration.new)
    Dir.mktmpdir("rails-migrations2sql-install") do |directory|
      capture_io do
        RailsMigrations2sql::Generators::InstallGenerator.new([], {}, destination_root: directory).invoke_all
      end
      load File.join(directory, "config/initializers/rails_migrations2sql.rb")
      RailsMigrations2sql::OfflineGuard.protect do
        assert_equal :oracle, RailsMigrations2sql.configuration.target
      end
    end
  ensure
    RailsMigrations2sql.instance_variable_set(:@configuration, previous)
  end

  private

  def set_adapter(adapter)
    ActiveRecord::Base.configurations = { "test" => { "adapter" => adapter } }
  end
end
