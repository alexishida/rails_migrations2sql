# frozen_string_literal: true

require_relative "test_helper"

class SqlRegressionsTest < Minitest::Test
  def compilers
    RailsMigrations2sql::Configuration::SUPPORTED_TARGETS.map do |target|
      RailsMigrations2sql::CompilerFactory.build(target, RailsMigrations2sql::Configuration.new)
    end
  end

  def operation(name, *args, **options)
    RailsMigrations2sql::Operation.new(name: name, args: args, options: options)
  end

  def evaluate(&block)
    klass = Class.new do
      def initialize(*) = nil
    end
    klass.define_method(:change, &block)
    RailsMigrations2sql::MigrationEvaluator.new(
      migration_file: RailsMigrations2sql::MigrationFile.new(path: __FILE__, version: "1", name: "regression", class_name: "Regression"),
      migration_class: klass,
      compiler: RailsMigrations2sql::Compilers::PostgreSQL.new
    ).evaluate
  end

  def test_false_default_is_preserved_for_every_dialect
    compilers.each do |compiler|
      sql = compiler.compile([operation(:change_column_default, :users, :active, { from: true, to: false })]).join("\n")
      assert_includes sql, "DEFAULT #{compiler.boolean_literal(false)}", compiler.target.to_s
    end
  end

  def test_null_backfill_precedes_constraint_for_every_dialect
    compilers.each do |compiler|
      statements = compiler.compile([operation(:change_column_null, :users, :active, false, false, current_type: :boolean)])
      expected = "UPDATE #{compiler.quote_table(:users)} SET #{compiler.quote_column(:active)} = #{compiler.boolean_literal(false)} WHERE #{compiler.quote_column(:active)} IS NULL"
      assert_equal expected, statements.first, compiler.target.to_s
      assert_includes statements.last, "NOT NULL"
      assert statements.all? { |statement| statement.is_a?(String) }
      assert_equal 1, compiler.compile([operation(:change_column_null, :users, :active, true, false, current_type: :boolean)]).length
    end
  end

  def test_composite_primary_key_does_not_create_a_synthetic_column
    result = evaluate do
      create_table :memberships, primary_key: [:user_id, :group_id] do |t|
        t.bigint :user_id, :group_id, null: false
      end
    end
    compilers.each do |compiler|
      sql = compiler.compile(result.up_operations).first
      assert_equal 1, sql.scan("PRIMARY KEY").length
      assert_includes sql, "PRIMARY KEY (#{compiler.quote_column(:user_id)}, #{compiler.quote_column(:group_id)})"
      refute_match(/IDENTITY|AUTO_INCREMENT/, sql)
    end
  end

  def test_uuid_primary_key_has_no_integer_identity
    result = evaluate { create_table :tokens, id: :uuid }
    compilers.each do |compiler|
      refute_match(/IDENTITY|AUTO_INCREMENT/, compiler.compile(result.up_operations).first)
    end
  end

  def test_mysql_foreign_key_removal_uses_dialect_syntax
    compilers.select { |compiler| [:mysql, :mariadb].include?(compiler.target) }.each do |compiler|
      sql = compiler.compile([operation(:remove_foreign_key, :orders, :users, name: :orders_user_fk)]).first
      assert_equal "ALTER TABLE `orders` DROP FOREIGN KEY `orders_user_fk`", sql
    end
  end

  def test_sqlserver_remove_columns_drops_defaults_in_separate_scopes
    compiler = RailsMigrations2sql::Compilers::SQLServer.new
    sql = compiler.compile([operation(:remove_columns, :users, :name, :active)])
    assert_equal 4, sql.length
    assert_match(/\AEXEC sys\.sp_executesql N'/, sql[0])
    assert_equal "ALTER TABLE [users] DROP COLUMN [name]", sql[1]
    assert_match(/\AEXEC sys\.sp_executesql N'/, sql[2])
    assert_equal "ALTER TABLE [users] DROP COLUMN [active]", sql[3]
  end

  def test_sqlserver_change_column_includes_default_change
    compiler = RailsMigrations2sql::Compilers::SQLServer.new
    sql = compiler.compile([operation(:change_column, :users, :active, :boolean, default: false, null: false)]).join("\n")
    assert_includes sql, "ALTER COLUMN [active] bit NOT NULL"
    assert_includes sql, "DEFAULT 0 FOR [active]"
  end

  def test_index_accepts_scalar_order_and_keyword_column_on_removal
    result = evaluate do
      create_table(:users) { |t| t.string :name }
      add_index :users, :name, order: :desc
      remove_index :users, column: :name
    end
    compilers.each do |compiler|
      sql = compiler.compile(result.up_operations)
      assert_includes sql[1], "#{compiler.quote_column(:name)} DESC"
      assert_includes sql[2], compiler.quote_identifier("index_users_on_name")
    end
    refute result.schema_after.index_exists?(:users, :name)
  end

  def test_schema_copy_supports_expression_defaults_and_is_isolated
    schema = RailsMigrations2sql::VirtualSchema.new
    expression = -> { "CURRENT_TIMESTAMP" }
    schema.create_table(:events, columns: [{ name: :created_at, type: :datetime, options: { default: expression, metadata: { tags: ["original"] } } }])
    copy = schema.dup
    copy.column(:events, :created_at).options[:metadata][:tags] << "copy"
    assert_equal ["original"], schema.column(:events, :created_at).options[:metadata][:tags]
    assert_equal "CURRENT_TIMESTAMP", copy.column(:events, :created_at).options[:default].call
  end

  def test_reversible_group_applies_schema_changes_once
    result = evaluate do
      create_table(:users) { |t| t.string :name }
      reversible do |dir|
        dir.up do
          add_column :users, :active, :boolean, default: true
          change_column_default :users, :active, from: true, to: false
          rename_column :users, :name, :display_name
        end
      end
    end
    assert result.schema_after.column_exists?(:users, :display_name)
    refute_nil result.schema_after.column(:users, :active)
    assert_equal false, result.schema_after.column(:users, :active).options[:default]
  end

  def test_reversible_group_does_not_repeat_column_swaps
    result = evaluate do
      create_table(:users) do |t|
        t.string :name
        t.integer :age
      end
      reversible do |dir|
        dir.up do
          rename_column :users, :name, :temporary
          rename_column :users, :age, :name
          rename_column :users, :temporary, :age
        end
      end
    end
    assert_equal :integer, result.schema_after.column(:users, :name).type
    assert_equal :string, result.schema_after.column(:users, :age).type
  end

  def test_connection_execute_uses_current_recorder_inside_revert
    result = evaluate do
      connection
      revert do
        connection.execute "DELETE FROM users"
      end
    end
    flunk "Expected irreversible SQL to be rejected: #{result.up_operations.inspect}"
  rescue RailsMigrations2sql::IrreversibleOperationError
    assert true
  end

  def test_revert_preserves_false_default
    result = evaluate do
      revert { change_column_default :users, :active, from: false, to: true }
    end
    assert_equal false, result.up_operations.first.args[2][:to]
  end

  def test_schema_tracks_remove_columns_and_unique_index_predicates
    result = evaluate do
      create_table(:users) { |t| t.string :name, :old_name }
      add_index :users, :name
      raise "wrong uniqueness" if index_exists?(:users, :name, unique: true)
      remove_columns :users, :name, :old_name
    end
    refute result.schema_after.column_exists?(:users, :name)
    refute result.schema_after.column_exists?(:users, :old_name)
  end

  def test_constraint_names_match_active_record
    adapter = ActiveRecord::ConnectionAdapters::AbstractAdapter.new(adapter: "abstract")
    compiler = RailsMigrations2sql::Compilers::PostgreSQL.new
    columns = [:user_id, :tenant_id]
    name = adapter.send(:foreign_key_name, "orders", column: columns)
    assert_equal name, RailsMigrations2sql::Util.default_foreign_key_name("orders", columns)
    name = adapter.send(:check_constraint_name, "orders", expression: "total > 0")
    sql = compiler.compile([operation(:add_check_constraint, :orders, "total > 0")]).first
    assert_includes sql, compiler.quote_identifier(name)
  end
end
