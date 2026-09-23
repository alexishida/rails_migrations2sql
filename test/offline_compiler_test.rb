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
        dir.down { raise "Rollback must not be evaluated" }
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

  def test_change_generates_application_sql_without_database
    compiler = RailsMigrations2sql::Compilers::PostgreSQL.new
    result = evaluate(FakeMigration, compiler)

    assert_equal :create_table, result.up_operations.first.name

    up = compiler.compile(result.up_operations).join("\n")

    assert_includes up, 'CREATE TABLE "orders"'
    assert_includes up, 'ALTER TABLE "orders" ADD "status" varchar(255) DEFAULT \'pending\' NOT NULL'
    assert_includes up, 'CREATE UNIQUE INDEX "index_orders_on_status"'
  end

  def test_reversible_evaluates_only_the_up_block
    compiler = RailsMigrations2sql::Compilers::PostgreSQL.new
    result = evaluate(ReversibleMigration, compiler)

    sql = compiler.compile(result.up_operations)
    assert_match(/ADD "active"/, sql.first)
    assert_match(/CREATE VIEW active_users/, sql.last)
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

  def test_execute_in_change_does_not_require_rollback
    klass = Class.new do
      def initialize(*) = nil
      def change = execute("UPDATE users SET active = 1")
    end

    compiler = RailsMigrations2sql::Compilers::PostgreSQL.new
    result = evaluate(klass, compiler)

    assert_includes compiler.compile(result.up_operations).first, "UPDATE users"
  end
end
