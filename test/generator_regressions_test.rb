# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class GeneratorRegressionsTest < Minitest::Test
  class << self
    attr_accessor :loads, :evaluations, :snapshot_loads
  end

  def with_project
    Dir.mktmpdir("sql-generator-regression") do |root|
      migrations = File.join(root, "migrate")
      Dir.mkdir(migrations)
      File.write(File.join(migrations, "20260101000000_generator_probe.rb"), <<~SOURCE)
        GeneratorRegressionsTest.loads += 1
        class GeneratorProbe < ActiveRecord::Migration[8.0]
          def change
            GeneratorRegressionsTest.evaluations << connection.adapter_name
            raise "Schema leaked between targets" if column_exists?(:existing, :visited)
            add_column :existing, :visited, :string
            create_table(:events) { |t| t.datetime :created_at, default: -> { "CURRENT_TIMESTAMP" } }
          end
        end
      SOURCE
      File.write(File.join(migrations, "20260101000001_generator_followup.rb"), <<~SOURCE)
        GeneratorRegressionsTest.loads += 1
        class GeneratorFollowup < ActiveRecord::Migration[8.0]
          def change
            raise "Schema was lost between migrations" unless column_exists?(:existing, :visited)
            add_column :events, :name, :string
          end
        end
      SOURCE
      snapshot = File.join(root, "schema.rb")
      File.write(snapshot, <<~SOURCE)
        ActiveRecord::Schema[8.0].define(version: 0) do
          GeneratorRegressionsTest.snapshot_loads += 1
          create_table(:existing) { |t| t.string :name }
        end
      SOURCE
      config = RailsMigrations2sql::Configuration.new
      config.migrations_paths = [migrations]
      config.output_path = File.join(root, "sql")
      config.use_schema_snapshot = true
      config.schema_path = snapshot
      self.class.loads = 0
      self.class.evaluations = []
      self.class.snapshot_loads = 0
      yield config
    ensure
      Object.send(:remove_const, :GeneratorProbe) if Object.const_defined?(:GeneratorProbe)
      Object.send(:remove_const, :GeneratorFollowup) if Object.const_defined?(:GeneratorFollowup)
    end
  end

  def test_loads_sources_once_but_evaluates_each_target_with_its_own_schema
    with_project do |config|
      result = RailsMigrations2sql::Generator.new(config).generate(all: true, target: :all)
      assert_equal 10, result.packages.length
      assert_equal 2, self.class.loads
      assert_equal 1, self.class.snapshot_loads
      assert_equal ["PostgreSQL", "Mysql2", "Mysql2", "OracleEnhanced", "SQLServer"], self.class.evaluations
    end
  end

  def test_targets_are_normalized_and_deduplicated
    with_project do |config|
      result = RailsMigrations2sql::Generator.new(config).generate(all: true, target: "PostgreSQL, postgresql")
      assert_equal [:postgresql], result.targets
      assert_equal 2, result.packages.length
      assert_equal ["PostgreSQL"], self.class.evaluations
    end
  end

  def test_blank_targets_are_rejected_before_loading_migrations
    with_project do |config|
      assert_raises(RailsMigrations2sql::ConfigurationError) do
        RailsMigrations2sql::Generator.new(config).generate(all: true, target: " , ")
      end
      assert_equal 0, self.class.loads
      assert_empty Dir[File.join(config.output_path, "**", "*.sql")]
    end
  end

  def test_all_does_not_hide_invalid_targets
    with_project do |config|
      error = assert_raises(RailsMigrations2sql::ConfigurationError) do
        RailsMigrations2sql::Generator.new(config).generate(all: true, target: "all,typo")
      end
      assert_includes error.message, "typo"
      assert_equal 0, self.class.loads
    end
  end

  def test_invalid_version_bounds_do_not_select_unintended_migrations
    with_project do |config|
      generator = RailsMigrations2sql::Generator.new(config)
      [{ from: "typo" }, { to: "20260101000000oops" }, { from: "" },
       { from: "20260101000001", to: "20260101000000" }].each do |bounds|
        assert_raises(RailsMigrations2sql::ConfigurationError) do
          generator.generate(**bounds, target: :postgresql)
        end
      end
      assert_equal 0, self.class.loads
      assert_empty Dir[File.join(config.output_path, "**", "*.sql")]
    end
  end

  def test_failure_in_later_migration_preserves_existing_files
    with_project do |config|
      generator = RailsMigrations2sql::Generator.new(config)
      result = generator.generate(all: true, target: :postgresql)
      before = result.packages.to_h { |path| [path, File.binread(path)] }
      first, last = Dir[File.join(config.migrations_paths.first, "*.rb")].sort
      File.write(first, File.read(first).sub("t.datetime :created_at", "t.datetime :modified_at"))
      File.write(last, File.read(last).sub('add_column :events, :name, :string', 'raise "Later migration failed"'))

      assert_raises(RailsMigrations2sql::OfflineCompilationError) { generator.generate(all: true, target: :postgresql) }
      assert_equal before, result.packages.to_h { |path| [path, File.binread(path)] }
    end
  end

  def test_failure_in_later_dialect_does_not_leave_partial_output
    with_project do |config|
      first = Dir[File.join(config.migrations_paths.first, "*.rb")].sort.first
      File.write(first, File.read(first).sub('create_table(:events)', 'enable_extension :pgcrypto; create_table(:events)'))
      assert_raises(RailsMigrations2sql::UnsupportedOperationError) do
        RailsMigrations2sql::Generator.new(config).generate(all: true, target: "postgresql,mysql")
      end
      assert_empty Dir[File.join(config.output_path, "**", "*.sql")]
    end
  end

  def test_reloading_migration_does_not_keep_a_removed_change_method
    with_project do |config|
      generator = RailsMigrations2sql::Generator.new(config)
      generator.generate(version: "20260101000000", target: :postgresql)
      path = Dir[File.join(config.migrations_paths.first, "*.rb")].sort.first
      File.write(path, <<~RUBY)
        class GeneratorProbe < ActiveRecord::Migration[8.0]
          def up
            execute "SELECT 'new up method'"
          end
        end
      RUBY
      result = generator.generate(version: "20260101000000", target: :postgresql)
      sql = File.read(result.packages.first)
      assert_includes sql, "new up method"
      refute_includes sql, "CREATE TABLE"
    end
  end

  def test_duplicate_versions_are_rejected_before_evaluation
    with_project do |config|
      path = File.join(config.migrations_paths.first, "20260101000000_duplicate.rb")
      File.write(path, "raise 'Should not load'\n")
      assert_raises(RailsMigrations2sql::ConfigurationError) do
        RailsMigrations2sql::Generator.new(config).generate(all: true, target: :postgresql)
      end
      assert_equal 0, self.class.loads
    end
  end

  def test_migration_sources_and_snapshot_are_reloaded_on_next_generation
    with_project do |config|
      generator = RailsMigrations2sql::Generator.new(config)
      generator.generate(all: true, target: :postgresql)
      generator.generate(all: true, target: :postgresql)
      assert_equal 4, self.class.loads
      assert_equal 2, self.class.snapshot_loads
    end
  end
end
