# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class GeneratorTest < Minitest::Test
  def test_from_generates_one_sql_per_migration_and_dialect_with_registration_last
    Dir.mktmpdir("rails-migrations2sql-test") do |directory|
      config = configuration(directory)
      result = RailsMigrations2sql::Generator.new(config).generate(from: "20260923130000", target: "all")

      assert_equal 10, result.packages.length
      generated_files = Dir[File.join(directory, "**", "*")].select { |path| File.file?(path) }
      assert_equal result.packages.sort, generated_files.sort
      result.packages.each do |path|
        assert_match(/202609231(?:30000|31500)_sql_export_\w+\.sql\z/, path)
        sql = File.read(path)
        assert_equal 1, sql.scan(/INSERT INTO/).length
        assert_match(/INSERT INTO .*schema_migrations.*202609231(?:30000|31500)/i, sql)
        assert sql.index("INSERT INTO") > sql.index(path.include?("create_articles") ? "CREATE TABLE" : "UPDATE articles")
        refute_includes sql, "DROP TABLE"
      end
      assert_empty Dir[File.join(directory, "**", "{up,down,register,unregister}.sql")]
    end
  end

  def test_default_output_is_db_sql_and_repeat_generation_overwrites_the_same_file
    Dir.mktmpdir("rails-migrations2sql-test") do |directory|
      config = configuration(nil)
      Dir.chdir(directory) do
        generator = RailsMigrations2sql::Generator.new(config)
        first = generator.generate(version: "20260923130000")
        second = generator.generate(version: "20260923130000")

        assert_equal first.packages, second.packages
        assert_equal [File.join(directory, "db/sql/postgresql/20260923130000_sql_export_create_articles.sql")], first.packages
        assert_equal 1, Dir["db/sql/**/*.sql"].length
      end
    end
  end

  def test_query_during_migration_loading_is_blocked_before_writing_sql
    Dir.mktmpdir("rails-migrations2sql-test") do |directory|
      config = configuration(directory)
      config.migrations_paths = [File.expand_path("fixtures/unsafe_migrations", __dir__)]
      original = ActiveRecord::Base.connection_handler

      assert_raises(RailsMigrations2sql::UnsupportedOperationError) do
        RailsMigrations2sql::Generator.new(config).generate(all: true)
      end
      assert_empty Dir[File.join(directory, "**", "*.sql")]
      assert_same original, ActiveRecord::Base.connection_handler
    end
  end

  private

  def configuration(output_path)
    RailsMigrations2sql::Configuration.new.tap do |config|
      config.target = :postgresql
      config.output_path = output_path
      config.migrations_paths = [File.expand_path("fixtures/migrations", __dir__)]
    end
  end
end
