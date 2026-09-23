# frozen_string_literal: true

require_relative "test_helper"

class OfflineQueriesTest < Minitest::Test
  class Article < ActiveRecord::Base
    self.table_name = "articles"
  end

  %i[select_value select_values select_all select_rows select_one exec_query exec_select].each do |query|
    define_method("test_direct_#{query}_reports_an_offline_error") do
      migration = Class.new(ActiveRecord::Migration[8.0]) do
        define_method(:up) { public_send(query, "SELECT COUNT(*) FROM articles", prepare: false) }
      end

      error = assert_raises(RailsMigrations2sql::UnsupportedOperationError) { evaluate(migration) }
      assert_includes error.message, "#{query} requires a real database connection"
      assert_includes error.message, "use execute"
    end

    define_method("test_connection_#{query}_reports_an_offline_error") do
      migration = Class.new(ActiveRecord::Migration[8.0]) do
        define_method(:change) { connection.public_send(query, "SELECT COUNT(*) FROM articles") }
      end

      error = assert_raises(RailsMigrations2sql::UnsupportedOperationError) { evaluate(migration) }
      assert_includes error.message, "connection.#{query}"
    end
  end

  def test_down_with_query_is_never_evaluated
    migration = Class.new(ActiveRecord::Migration[8.0]) do
      def up = add_column(:articles, :category, :string)
      def down = select_value("SELECT COUNT(*) FROM articles")
    end

    assert_equal [:add_column], evaluate(migration).up_operations.map(&:name)
  end

  def test_change_is_evaluated_once_and_takes_precedence_over_up
    calls = 0
    migration = Class.new(ActiveRecord::Migration[8.0]) do
      define_method(:change) do
        calls += 1
        execute "UPDATE articles SET category = 'general'"
      end
      def up = raise("change must take precedence")
      def down = raise("down must not be evaluated")
    end

    result = evaluate(migration)
    assert_equal 1, calls
    assert_equal [:execute], result.up_operations.map(&:name)
  end

  def test_model_reads_are_blocked
    migration = Class.new(ActiveRecord::Migration[8.0]) do
      define_method(:up) { Article.count }
    end

    error = assert_raises(RailsMigrations2sql::UnsupportedOperationError) { evaluate(migration) }
    assert_includes error.message, "Active Record database access"
  end

  def test_model_writes_are_blocked
    migration = Class.new(ActiveRecord::Migration[8.0]) do
      define_method(:up) { Article.where(category: nil).update_all(category: "general") }
    end

    assert_raises(RailsMigrations2sql::UnsupportedOperationError) { evaluate(migration) }
  end

  def test_original_connection_handler_is_not_used_and_is_restored_after_failure
    original = ActiveRecord::Base.connection_handler
    handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
    accesses = 0
    handler.define_singleton_method(:retrieve_connection_pool) do |*|
      accesses += 1
      raise "The application connection handler must not be used"
    end
    ActiveRecord::Base.connection_handler = handler

    migration = Class.new(ActiveRecord::Migration[8.0]) do
      define_method(:up) { Article.count }
    end

    assert_raises(RailsMigrations2sql::UnsupportedOperationError) { evaluate(migration) }
    assert_equal 0, accesses
    assert_same handler, ActiveRecord::Base.connection_handler
  ensure
    ActiveRecord::Base.connection_handler = original
  end

  def test_guard_restores_context_after_success_nested_calls_and_ruby_failure
    original = ActiveRecord::Base.connection_handler
    RailsMigrations2sql::OfflineGuard.protect do
      outer = ActiveRecord::Base.connection_handler
      RailsMigrations2sql::OfflineGuard.protect { assert_raises(RailsMigrations2sql::UnsupportedOperationError) { Article.count } }
      assert_same outer, ActiveRecord::Base.connection_handler
      refute_kind_of RailsMigrations2sql::OfflineGuard::ConnectionHandler, Thread.new { ActiveRecord::Base.connection_handler }.value
    end
    assert_same original, ActiveRecord::Base.connection_handler

    assert_raises(RuntimeError) { RailsMigrations2sql::OfflineGuard.protect { raise "failure" } }
    assert_same original, ActiveRecord::Base.connection_handler
  end

  def test_guard_rejects_establishing_a_connection
    RailsMigrations2sql::OfflineGuard.protect do
      assert_raises(RailsMigrations2sql::UnsupportedOperationError) do
        ActiveRecord::Base.connection_handler.establish_connection({ adapter: "sqlite3", database: ":memory:" })
      end
    end
  end

  private

  def evaluate(migration)
    RailsMigrations2sql::MigrationEvaluator.new(
      migration_file: RailsMigrations2sql::MigrationFile.new(
        path: __FILE__, version: "20260923130000", name: "query_migration", class_name: "QueryMigration"
      ),
      migration_class: migration,
      compiler: RailsMigrations2sql::Compilers::PostgreSQL.new
    ).evaluate
  end
end
