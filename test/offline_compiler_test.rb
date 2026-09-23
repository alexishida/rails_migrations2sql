# frozen_string_literal: true

require_relative "test_helper"

class OfflineCompilerTest < Minitest::Test
  FakeMigration = Class.new do
    def initialize(*) = nil

    def change
      create_table :orders do |t|
        t.string :number, null: false
        t.decimal :total, precision: 12, scale: 2
        t.references :customer, null: false, foreign_key: true
        t.timestamps
      end
      add_column :orders, :status, :string, null: false, default: "pending"
      add_index :orders, :status, unique: true
    end
  end

  ReversibleMigration = Class.new do
    def initialize(*) = nil

    def change
      add_column :users, :active, :boolean, default: false, null: false
      reversible do |dir|
        dir.up { execute "CREATE VIEW active_users AS SELECT * FROM users WHERE active = 1" }
        dir.down { execute "DROP VIEW active_users" }
      end
    end
  end

  def migration_file(name = "fake_migration")
    RailsMigrations2sql::MigrationFile.new(
      path: __FILE__, version: "20260923130000", name: name, class_name: "FakeMigration"
    )
  end

  def evaluate(klass, compiler)
    RailsMigrations2sql::MigrationEvaluator.new(
      migration_file: migration_file,
      migration_class: klass,
      compiler: compiler,
      base_schema: RailsMigrations2sql::VirtualSchema.new
    ).evaluate
  end

  def test_change_generates_up_and_down_without_database
    compiler = RailsMigrations2sql::Compilers::PostgreSQL.new
    result = evaluate(FakeMigration, compiler)

    assert result.rollback_available
    assert_equal :create_table, result.up_operations.first.name
    assert_equal :remove_index, result.down_operations.first.name
    assert_equal :drop_table, result.down_operations.last.name

    up = compiler.compile(result.up_operations).join("\n")
    down = compiler.compile(result.down_operations).join("\n")

    assert_includes up, 'CREATE TABLE "orders"'
    assert_includes up, 'ALTER TABLE "orders" ADD "status" varchar(255) DEFAULT \'pending\' NOT NULL'
    assert_includes up, 'CREATE UNIQUE INDEX "index_orders_on_status"'
    assert_includes down, 'DROP INDEX "index_orders_on_status"'
    assert_includes down, 'DROP TABLE "orders"'
  end

  def test_reversible_keeps_explicit_down_sql_in_correct_order
    compiler = RailsMigrations2sql::Compilers::PostgreSQL.new
    result = evaluate(ReversibleMigration, compiler)

    assert result.rollback_available
    down = compiler.compile(result.down_operations)
    assert_match(/DROP VIEW active_users/, down.first)
    assert_match(/DROP COLUMN "active"/, down.last)
  end

  def test_all_dialects_compile_add_column
    op = RailsMigrations2sql::Operation.new(
      name: :add_column,
      args: [:orders, :status, :string],
      options: { null: false, default: "pending" }
    )

    compilers = [
      RailsMigrations2sql::Compilers::PostgreSQL.new,
      RailsMigrations2sql::Compilers::MySQL.new,
      RailsMigrations2sql::Compilers::MariaDB.new,
      RailsMigrations2sql::Compilers::Oracle.new,
      RailsMigrations2sql::Compilers::SQLServer.new
    ]

    compilers.each do |compiler|
      sql = compiler.compile([op]).first
      assert_includes sql.downcase, "alter table"
      assert_includes sql.downcase, "status"
      assert_includes sql.downcase, "pending"
    end
  end

  def test_irreversible_execute_in_change_marks_rollback_unavailable
    klass = Class.new do
      def initialize(*) = nil
      def change = execute("UPDATE users SET active = 1")
    end

    compiler = RailsMigrations2sql::Compilers::PostgreSQL.new
    result = evaluate(klass, compiler)

    refute result.rollback_available
    assert_match(/execute is not automatically reversible/, result.rollback_error)
    assert_includes compiler.compile(result.up_operations).first, "UPDATE users"
  end
end
