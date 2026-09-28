# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class MigrationLoaderTest < Minitest::Test
  def with_source(source)
    Dir.mktmpdir("migration-loader") do |root|
      path = File.join(root, "20260101000000_compatibility_migration.rb")
      File.write(path, source)
      migration = RailsMigrations2sql::MigrationFile.new(
        path: path, version: "20260101000000", name: "compatibility_migration", class_name: "CompatibilityMigration"
      )
      yield migration, root
    end
  end

  def test_loading_preserves_file_context_and_relative_requires_without_leaking_constants
    with_source(<<~SOURCE) do |migration, root|
      # frozen_string_literal: true
      require_relative "support"
      class CompatibilityMigration < ActiveRecord::Migration[#{MIGRATION_VERSION}]
        SOURCE_PATH = __FILE__
        SOURCE_DIRECTORY = __dir__
        LABEL = "frozen source literal"
        def change
          execute MigrationLoaderSupport.statement
        end
      end
    SOURCE
      File.write(File.join(root, "support.rb"), <<~SOURCE)
        module MigrationLoaderSupport
          def self.statement
            "SELECT 'relative require'"
          end
        end
      SOURCE
      klass = RailsMigrations2sql::MigrationLoader.new.load_class(migration)
      assert_equal migration.path, klass::SOURCE_PATH
      assert_equal root, klass::SOURCE_DIRECTORY
      assert klass::LABEL.frozen?
      refute Object.const_defined?(:CompatibilityMigration, false)
      result = RailsMigrations2sql::MigrationEvaluator.new(
        migration_file: migration, migration_class: klass,
        compiler: RailsMigrations2sql::Compilers::PostgreSQL.new
      ).evaluate
      assert_equal ["SELECT 'relative require'"], result.up_operations.first.args
    end
  ensure
    Object.send(:remove_const, :MigrationLoaderSupport) if Object.const_defined?(:MigrationLoaderSupport, false)
  end

  def test_loading_returns_a_fresh_class_without_reusing_previous_methods
    with_source(<<~SOURCE) do |migration, _|
      class CompatibilityMigration < ActiveRecord::Migration[#{MIGRATION_VERSION}]
        def change
          execute "SELECT 'old source'"
        end
      end
    SOURCE
      loader = RailsMigrations2sql::MigrationLoader.new
      previous = loader.load_class(migration)
      File.write(migration.path, <<~SOURCE)
        class CompatibilityMigration < ActiveRecord::Migration[#{MIGRATION_VERSION}]
          def up
            execute "SELECT 'new source'"
          end
        end
      SOURCE
      current = loader.load_class(migration)
      refute_same previous, current
      refute_includes current.instance_methods(false), :change
      assert_includes current.instance_methods(false), :up
    end
  end

  def test_loading_errors_include_the_original_file_and_line
    with_source("# first line\nraise 'source failure'\n") do |migration, _|
      error = assert_raises(RailsMigrations2sql::OfflineCompilationError) do
        RailsMigrations2sql::MigrationLoader.new.load_class(migration)
      end
      assert_includes error.message, migration.path
      assert_includes error.cause.backtrace.first, "#{migration.path}:2"
    end
  end
end
