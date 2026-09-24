# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "rake"

class SeedGeneratorTest < Minitest::Test
  class SeedArticle < ActiveRecord::Base
    self.table_name = "seed_articles"
  end

  def test_migration_generation_also_writes_seeds_for_each_target
    with_seed_file(<<~RUBY) do |config|
      SeedGeneratorTest::SeedArticle.create!(id: 1, title: "D'Artagnan", published: true)
      SeedGeneratorTest::SeedArticle.insert_all([{ id: 2, title: "Second", published: false }])
    RUBY
      config.migrations_paths = [File.expand_path("fixtures/migrations", __dir__)]
      result = RailsMigrations2sql::Generator.new(config).generate(version: "20260923130000", target: "postgresql,mysql")

      assert_equal 4, result.packages.length
      assert_equal 2, result.packages.count { |path| path.end_with?("seeds.sql") }
      postgres = File.read(File.join(config.output_path, "postgresql", "seeds.sql"))
      mysql = File.read(File.join(config.output_path, "mysql", "seeds.sql"))
      assert_includes postgres, %(INSERT INTO "seed_articles" ("id", "title", "published") VALUES (1, 'D''Artagnan', TRUE);)
      assert_includes mysql, "INSERT INTO `seed_articles` (`id`, `title`, `published`) VALUES (1, 'D''Artagnan', 1);"
      assert_equal 2, postgres.scan(/INSERT INTO/).length
    end
  end

  def test_find_or_create_by_generates_conditional_insert_with_block_values
    with_seed_file(<<~RUBY) do |config|
      SeedGeneratorTest::SeedArticle.find_or_create_by!(title: "Existing", category: nil) do |article|
        article.published = true
      end
    RUBY
      result = RailsMigrations2sql::Generator.new(config).generate_seeds(target: "postgresql,oracle")
      assert_equal 2, result.packages.length
      postgres = File.read(File.join(config.output_path, "postgresql", "seeds.sql"))
      oracle = File.read(File.join(config.output_path, "oracle", "seeds.sql"))
      assert_includes postgres, %(INSERT INTO "seed_articles" ("title", "category", "published") SELECT 'Existing', NULL, TRUE WHERE NOT EXISTS (SELECT 1 FROM "seed_articles" WHERE "title" = 'Existing' AND "category" IS NULL);)
      assert_includes oracle, "FROM DUAL WHERE NOT EXISTS"
    end
  end

  def test_seed_only_generation_writes_no_migration_sql_and_overwrites_file
    with_seed_file("SeedGeneratorTest::SeedArticle.create!(id: 1, title: 'First')\n") do |config|
      generator = RailsMigrations2sql::Generator.new(config)
      first = generator.generate_seeds
      File.write(config.seeds_path, "SeedGeneratorTest::SeedArticle.create!(id: 2, title: 'Second')\n")
      second = generator.generate_seeds

      assert_equal first.packages, second.packages
      assert_empty second.migrations
      assert_equal [File.join(config.output_path, "postgresql", "seeds.sql")], second.packages
      assert_equal second.packages, Dir[File.join(config.output_path, "**", "*.sql")]
      sql = File.read(second.packages.first)
      assert_includes sql, "VALUES (2, 'Second')"
      refute_includes sql, "First"
    end
  end

  def test_seed_query_is_blocked_and_does_not_write_sql
    with_seed_file("SeedGeneratorTest::SeedArticle.first\n") do |config|
      original_handler = ActiveRecord::Base.connection_handler
      error = assert_raises(RailsMigrations2sql::UnsupportedOperationError) do
        RailsMigrations2sql::Generator.new(config).generate_seeds
      end
      assert_match(/database|connection/i, error.message)
      assert_empty Dir[File.join(config.output_path, "**", "*.sql")]
      assert_same original_handler, ActiveRecord::Base.connection_handler
    end
  end

  def test_invalid_seed_does_not_leave_migration_sql_from_same_run
    with_seed_file("SeedGeneratorTest::SeedArticle.first\n") do |config|
      assert_raises(RailsMigrations2sql::UnsupportedOperationError) do
        RailsMigrations2sql::Generator.new(config).generate(version: "20260923130000")
      end
      assert_empty Dir[File.join(config.output_path, "**", "*.sql")]
    end
  end

  def test_database_generated_id_cannot_be_used_by_later_seed
    with_seed_file("row = SeedGeneratorTest::SeedArticle.create!(title: 'First')\nSeedGeneratorTest::SeedArticle.create!(id: row.id, title: 'Second')\n") do |config|
      error = assert_raises(RailsMigrations2sql::UnsupportedOperationError) do
        RailsMigrations2sql::Generator.new(config).generate_seeds
      end
      assert_match(/database-generated/, error.message)
      assert_empty Dir[File.join(config.output_path, "**", "*.sql")]
    end
  end

  def test_standalone_rake_task_generates_only_seeds_sql
    with_seed_file("SeedGeneratorTest::SeedArticle.create!(id: 3, title: 'Task')\n") do |config|
      original_rake = Rake.application
      original_config = RailsMigrations2sql.configuration
      Rake.application = Rake::Application.new
      RailsMigrations2sql.instance_variable_set(:@configuration, config)
      Rake::Task.define_task(:environment)
      load File.expand_path("../lib/tasks/rails_migrations2sql.rake", __dir__)

      output, = capture_io { Rake::Task["dba:sql:seeds"].invoke }
      assert_includes output, "Compiled seeds for postgresql"
      assert_equal [File.join(config.output_path, "postgresql", "seeds.sql")], Dir[File.join(config.output_path, "**", "*.sql")]
    ensure
      Rake.application = original_rake
      RailsMigrations2sql.instance_variable_set(:@configuration, original_config)
    end
  end

  def test_missing_seed_file_is_optional_for_migrations_but_required_for_seed_command
    Dir.mktmpdir do |root|
      config = configuration(root)
      result = RailsMigrations2sql::Generator.new(config).generate(version: "20260923130000")
      assert_equal 1, result.packages.length
      error = assert_raises(RailsMigrations2sql::ConfigurationError) do
        RailsMigrations2sql::Generator.new(config).generate_seeds
      end
      assert_match(/Seed file not found/, error.message)
    end
  end

  private

  def with_seed_file(source)
    Dir.mktmpdir do |root|
      config = configuration(root)
      File.write(config.seeds_path, source)
      yield config
    end
  end

  def configuration(root)
    RailsMigrations2sql::Configuration.new.tap do |config|
      config.target = :postgresql
      config.output_path = File.join(root, "sql")
      config.seeds_path = File.join(root, "seeds.rb")
      config.migrations_paths = [File.expand_path("fixtures/migrations", __dir__)]
    end
  end
end
