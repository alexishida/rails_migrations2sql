# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class SeedScriptTest < Minitest::Test
  def with_project
    Dir.mktmpdir do |root|
      config = RailsMigrations2sql::Configuration.new
      config.target = :postgresql
      config.output_path = File.join(root, "sql")
      config.seeds_path = File.join(root, "seeds.rb")
      config.migrations_paths = [File.expand_path("fixtures/migrations", __dir__)]
      File.write(config.seeds_path, "raise 'Normal Rails seeds must not run'\n")
      path = File.join(root, "seeds_sql.rb")
      yield config, path
    end
  end

  def test_companion_is_used_automatically_and_reloaded_for_each_run
    with_project do |config, path|
      File.write(path, 'insert :items, { title: "First" }')
      generator = RailsMigrations2sql::Generator.new(config)
      result = generator.generate(from: "20260923130000", target: :all)
      assert_equal 15, result.packages.length
      File.write(path, 'insert :items, { title: "Updated" }')
      generator.generate(from: "20260923130000", target: :all)
      result.packages.grep(/seed.sql$/).each do |file|
        assert_includes File.read(file), "Updated"
        refute_includes File.read(file), "First"
      end
    end
  end

  def test_conditional_inserts_updates_and_expressions_use_the_target_dialect
    with_project do |config, path|
      File.write(path, <<~RUBY)
        insert :items, { title: "O'Brien", parent_id: nil, created_at: sql("CURRENT_TIMESTAMP") },
          unless_exists: { title: "O'Brien", parent_id: nil }
        update :items, { title: "Changed" }, where: { title: "O'Brien" }
      RUBY
      result = RailsMigrations2sql::Generator.new(config).generate_seeds(target: "postgresql,oracle")
      postgres, oracle = result.packages.map { |file| File.read(file) }
      assert_includes postgres, %(SELECT 'O''Brien', NULL, CURRENT_TIMESTAMP WHERE NOT EXISTS)
      assert_includes postgres, %("parent_id" IS NULL)
      assert_includes postgres, %(UPDATE "items" SET "title" = 'Changed' WHERE "title" = 'O''Brien')
      assert_includes oracle, "FROM DUAL WHERE NOT EXISTS"
      assert_includes oracle, '"ITEMS"'
    end
  end

  def test_invalid_companion_preserves_existing_migration_and_seed_files
    with_project do |config, path|
      File.write(path, "insert :items, { title: 'Before' }")
      generator = RailsMigrations2sql::Generator.new(config)
      files = generator.generate(all: true).packages
      before = files.to_h { |file| [file, File.binread(file)] }
      File.write(path, "insert :items, { title: 'Partial' }\nraise 'Failed'\n")
      assert_raises(RailsMigrations2sql::OfflineCompilationError) { generator.generate(all: true) }
      assert_equal before, files.to_h { |file| [file, File.binread(file)] }
    end
  end

  def test_companion_does_not_gain_database_access
    with_project do |config, path|
      File.write(path, "ActiveRecord::Base.connection_handler.establish_connection(adapter: 'postgresql')")
      original = ActiveRecord::Base.connection_handler
      error = assert_raises(RailsMigrations2sql::OfflineCompilationError) do
        RailsMigrations2sql::Generator.new(config).generate_seeds
      end
      assert_includes error.message, "Active Record database access"
      assert_same original, ActiveRecord::Base.connection_handler
      assert_empty Dir[File.join(config.output_path, "**", "*.sql")]
    end
  end

  def test_missing_explicit_companion_does_not_fall_back_to_normal_seeds
    with_project do |config, path|
      config.sql_seeds_path = path
      assert_raises(RailsMigrations2sql::ConfigurationError) do
        RailsMigrations2sql::Generator.new(config).generate(all: true)
      end
    end
  end

  def test_execute_preserves_each_statement_when_the_source_string_changes
    with_project do |config, path|
      File.write(path, <<~RUBY)
        statement = +"INSERT INTO items (title) VALUES ('First')"
        execute statement
        statement.replace("INSERT INTO items (title) VALUES ('Second')")
        execute statement
        statement.clear
      RUBY
      result = RailsMigrations2sql::Generator.new(config).generate_seeds(target: :all)
      result.packages.each do |file|
        statements = File.read(file).lines.grep(/^INSERT INTO/)
        assert_equal [
          "INSERT INTO items (title) VALUES ('First');\n",
          "INSERT INTO items (title) VALUES ('Second');\n"
        ], statements
      end
    end
  end

  def test_seed_selection_rejects_typos
    assert_equal :auto, RailsMigrations2sql::SeedScript.selection(nil)
    assert_equal false, RailsMigrations2sql::SeedScript.selection("0")
    assert_equal true, RailsMigrations2sql::SeedScript.selection("1")
    assert_raises(RailsMigrations2sql::ConfigurationError) { RailsMigrations2sql::SeedScript.selection("yes") }
  end
end
