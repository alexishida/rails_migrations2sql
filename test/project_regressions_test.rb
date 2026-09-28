# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class ProjectRegressionsTest < Minitest::Test
  def evaluate(target = :postgresql, &block)
    klass = Class.new(ActiveRecord::Migration[8.0])
    klass.define_method(:change, &block)
    compiler = RailsMigrations2sql::CompilerFactory.build(target)
    result = RailsMigrations2sql::MigrationEvaluator.new(
      migration_file: RailsMigrations2sql::MigrationFile.new(path: __FILE__, version: "1", name: "probe", class_name: "Probe"),
      migration_class: klass, compiler: compiler
    ).evaluate
    [result, compiler.compile(result.up_operations)]
  end

  def test_added_column_type_is_available_without_a_snapshot
    %i[mysql mariadb sqlserver].each do |target|
      result, sql = evaluate(target) do
        add_column :existing, :title, :string, limit: 80, default: "initial"
        change_column_default :existing, :title, "updated"
        change_column_null :existing, :title, false
      end
      assert_includes sql.last, "(80)"
      assert_includes sql.last, "NOT NULL"
      assert_equal "updated", result.schema_after.column(:existing, :title).options[:default]
    end
  end

  def test_schema_tracks_primary_keys_join_tables_and_dropped_tables
    result, sql = evaluate do
      create_table(:authors) { |t| t.string :name }
      raise "Missing primary key" unless column_exists?(:authors, :id)
      create_join_table :authors, :books
      raise "Missing join table" unless table_exists?(:authors_books)
      raise "Nullable join key" unless column_exists?(:authors_books, :author_id, :bigint, null: false)
      drop_join_table :authors, :books
      raise "Join table still exists" if table_exists?(:authors_books)
      drop_table :authors
      raise "Table still exists" if table_exists?(:authors)
    end
    refute result.schema_after.table_exists?(:authors)
    assert_includes sql[1], '"author_id" bigint NOT NULL'
  end

  def test_inline_indexes_are_compiled_and_removed_using_their_actual_names
    result, sql = evaluate do
      create_table(:users) { |t| t.string :email, index: { unique: true, name: "users_email_unique" } }
      remove_index :users, :email
    end
    assert_includes sql[1], 'CREATE UNIQUE INDEX "users_email_unique"'
    assert_equal 'DROP INDEX "users_email_unique"', sql.last
    refute result.schema_after.index_exists?(:users, :email)
  end

  def test_reference_metadata_is_removed_with_the_reference
    result, = evaluate do
      create_table :articles
      add_reference :articles, :author, foreign_key: { to_table: :people, name: "article_author_fk" }
      raise "Missing named foreign key" unless foreign_key_exists?(:articles, :people, name: "article_author_fk")
      remove_reference :articles, :author, foreign_key: { to_table: :people, name: "article_author_fk" }
    end
    refute result.schema_after.index_exists?(:articles, :author_id)
    refute result.schema_after.foreign_key_exists?(:articles, :people)
  end

  def test_snapshot_accepts_pathname_and_contains_the_primary_key
    Dir.mktmpdir do |root|
      path = Pathname.new(root).join("schema.rb")
      path.write("ActiveRecord::Schema[8.0].define(version: 1) do\n  create_table :users do |t|\n    t.string :name\n  end\nend\n")
      schema = RailsMigrations2sql::SchemaLoader.new(path).load
      assert schema.column_exists?(:users, :id, :bigint)
    end
  end

  def test_missing_snapshot_fails_explicitly
    assert_raises(RailsMigrations2sql::OfflineCompilationError) do
      RailsMigrations2sql::SchemaLoader.new("/missing/project/schema.rb").load
    end
  end

  def test_sql_with_a_leading_comment_is_terminated
    formatter = RailsMigrations2sql::SqlFormatter.new(:postgresql)
    assert_equal "-- explanation\nUPDATE users SET active = true;", formatter.format("-- explanation\nUPDATE users SET active = true")
    assert_equal "UPDATE users SET active = true -- explanation\n;", formatter.format("UPDATE users SET active = true -- explanation")
    assert_equal "-- comment only", formatter.format("-- comment only")
  end

  def test_sqlserver_unicode_and_dynamic_sql_have_one_unicode_prefix
    compiler = RailsMigrations2sql::Compilers::SQLServer.new
    assert_equal "N'ação 漢字'", compiler.literal("ação 漢字")
    sql = compiler.compile([RailsMigrations2sql::Operation.new(name: :remove_column, args: [:users, :title])]).join("\n")
    assert_includes sql, "EXEC sys.sp_executesql N'"
    refute_includes sql, "NN'"
  end

  def test_non_sql_numeric_values_are_rejected
    compiler = RailsMigrations2sql::Compilers::PostgreSQL.new
    [Float::NAN, Float::INFINITY, Complex(1, 2), Rational(1, 3)].each do |value|
      assert_raises(RailsMigrations2sql::UnsupportedOperationError) { compiler.literal(value) }
    end
  end

  def test_join_table_prefix_and_revert_restore_both_reference_columns
    _, sql = evaluate do
      revert do
        drop_join_table :catalog_authors, :catalog_books do |t|
          t.index :catalog_author_id
        end
      end
    end
    assert_includes sql.first, 'CREATE TABLE "catalog_authors_books"'
    assert_includes sql.first, '"catalog_author_id" bigint NOT NULL'
    assert_includes sql.first, '"catalog_book_id" bigint NOT NULL'
  end

  def test_unknown_column_predicate_does_not_invent_a_table
    schema = RailsMigrations2sql::VirtualSchema.new
    assert_raises(RailsMigrations2sql::UnknownSchemaStateError) { schema.column_exists?(:unknown, :name) }
    assert_raises(RailsMigrations2sql::UnknownSchemaStateError) { schema.table_exists?(:unknown) }
  end

  def test_postgresql_keeps_using_expression_and_conditional_indexes
    _, sql = evaluate do
      change_column :users, :age, :integer, using: "age::integer"
      add_index :users, "lower(email)", name: "email_lower", if_not_exists: true
      remove_index :users, name: "email_lower", if_exists: true
    end
    assert_includes sql[0], "USING age::integer"
    assert_includes sql[1], 'CREATE INDEX IF NOT EXISTS "email_lower" ON "users" (lower(email))'
    assert_equal 'DROP INDEX IF EXISTS "email_lower"', sql[2]
  end

  def test_mysql_strings_with_backslashes_use_mode_independent_literals
    %i[mysql mariadb].each do |target|
      compiler = RailsMigrations2sql::CompilerFactory.build(target)
      value = "path" + 92.chr + "name's"
      assert_equal "_utf8mb4 X'#{value.unpack1('H*')}'", compiler.literal(value)
    end
  end

  def test_unsupported_index_options_are_not_silently_ignored
    %i[oracle sqlserver].each do |target|
      assert_raises(RailsMigrations2sql::UnsupportedOperationError) do
        evaluate(target) { add_index :users, :name, using: :gin }
      end
    end
    assert_raises(RailsMigrations2sql::UnsupportedOperationError) do
      evaluate(:mysql) { add_index :users, :name, if_not_exists: true }
    end
  end

  def test_explicit_primary_key_has_identity_for_integer_columns
    RailsMigrations2sql::Configuration::SUPPORTED_TARGETS.each do |target|
      _, sql = evaluate(target) { create_table(:users, id: false) { |t| t.primary_key :code } }
      assert_match(/IDENTITY|AUTO_INCREMENT/, sql.first)
    end
  end

  def test_inverse_remove_columns_preserves_column_options
    _, sql = evaluate do
      revert { remove_columns :users, :first, :last, type: :string, limit: 80, null: false, default: "unknown" }
    end
    sql.each do |statement|
      assert_includes statement, "varchar(80) DEFAULT 'unknown' NOT NULL"
    end
  end
end
