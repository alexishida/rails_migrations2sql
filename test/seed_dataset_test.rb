# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"

class SeedDatasetTest < Minitest::Test
  class DatasetRecord < ActiveRecord::Base
    self.table_name = "dataset_records"
    alias_attribute :headline, :title
  end

  class DatasetParent < ActiveRecord::Base
    self.table_name = "dataset_parents"
    alias_attribute :slug, :identifier
  end

  def with_dataset(records, **options)
    Dir.mktmpdir do |root|
      path = File.join(root, "records.json")
      File.write(path, JSON.generate(records))
      config = RailsMigrations2sql::Configuration.new
      config.seed_sources_root = root
      config.output_path = File.join(root, "sql")
      config.seed_sources = [ { model: DatasetRecord, path: "records.json" }.merge(options) ]
      yield config, path
    end
  end

  def test_array_rows_aliases_defaults_and_positions_are_compiled
    with_dataset([ [ "First" ], [ "Second" ] ], columns: [ :headline ], defaults: { active: true },
                 types: { active: :numeric_boolean }, position: :position) do |config, _|
      result = RailsMigrations2sql::Generator.new(config).generate_seeds(target: "oracle,postgresql")
      oracle, postgres = result.packages.map { |file| File.read(file) }
      assert_includes oracle, '"DATASET_RECORDS_SEQ".NEXTVAL'
      assert_includes oracle, %("ACTIVE", "TITLE", "POSITION")
      assert_includes postgres, %(VALUES ('1', 'First', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP))
      assert_includes postgres, %(VALUES ('1', 'Second', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP))
      refute_includes postgres, '"headline"'
    end
  end

  def test_json_keys_and_non_numeric_primary_keys_are_explicit
    with_dataset({ "administrator" => { "email" => "admin@example.com", "headline" => "Admin" } },
                 key: :administrator, columns: %i[email headline], primary_key: :email) do |config, _|
      file = RailsMigrations2sql::Generator.new(config).generate_seeds(target: :oracle).packages.first
      content = File.read(file)
      assert_includes content, '"EMAIL", "TITLE"'
      refute_includes content, "NEXTVAL"
    end
  end

  def test_references_and_action_text_use_declared_lookups
    with_dataset([ { "headline" => "Article", "parent" => "guide", "body" => "<p>Body</p>" } ],
                 columns: [ :headline ], references: { parent_id: { model: DatasetParent, source: :parent, column: :slug } },
                 rich_texts: { body: { source: :body, lookup: :headline } }) do |config, _|
      file = RailsMigrations2sql::Generator.new(config).generate_seeds(target: :postgresql).packages.first
      content = File.read(file)
      assert_includes content, %(SELECT "id" FROM "dataset_parents" WHERE "identifier" = 'guide')
      assert_includes content, %(SELECT "id" FROM "dataset_records" WHERE "title" = 'Article')
      assert_includes content, %(INSERT INTO "action_text_rich_texts")
      assert_includes content, "'SeedDatasetTest::DatasetRecord'"
      assert_includes content, "'<p>Body</p>'"
    end
  end

  def test_literal_ids_custom_sequences_and_timestamp_settings_are_preserved
    with_dataset([ { "id" => 42, "headline" => "Explicit" } ], timestamps: false) do |config, _|
      config.seed_sources << { model: DatasetRecord, records: -> { { headline: "Identity" } }, timestamps: false, sequence: false }
      config.seed_sources << { model: DatasetRecord, records: -> { { headline: "Custom" } }, timestamps: false, sequence: "custom_ids" }
      file = RailsMigrations2sql::Generator.new(config).generate_seeds(target: :oracle).packages.first
      content = File.read(file)
      assert_includes content, %(VALUES (42, 'Explicit'))
      assert_includes content, %(INSERT INTO "DATASET_RECORDS" ("TITLE") VALUES ('Identity'))
      assert_includes content, '"CUSTOM_IDS".NEXTVAL'
      refute_includes content, "CURRENT_TIMESTAMP"
    end
  end

  def test_oracle_clob_chunks_round_trip_unicode_and_apostrophes
    body = "<p>ação 😀 ' &amp;</p>" * 1000
    with_dataset([ { "headline" => body } ], columns: [ :headline ], types: { headline: :text }) do |config, _|
      file = RailsMigrations2sql::Generator.new(config).generate_seeds(target: :oracle).packages.first
      literals = File.read(file).scan(/TO_CLOB\(('(?:''|[^'])*')\)/).flatten
      assert_operator literals.length, :>, 1
      assert literals.all? { |literal| literal.bytesize <= 4000 }
      assert_equal body, literals.map { |literal| literal[1...-1].gsub("''", "'") }.join
    end
  end

  def test_database_access_in_a_source_is_blocked_and_existing_output_is_preserved
    with_dataset([ { "headline" => "Before" } ]) do |config, _|
      generator = RailsMigrations2sql::Generator.new(config)
      file = generator.generate_seeds(target: :postgresql).packages.first
      before = File.binread(file)
      config.seed_sources = [ { model: DatasetRecord, records: -> { DatasetRecord.first } } ]
      original = ActiveRecord::Base.connection_handler
      error = assert_raises(RailsMigrations2sql::OfflineCompilationError) { generator.generate_seeds(target: :postgresql) }
      assert_includes error.message, "Active Record database access"
      assert_equal before, File.binread(file)
      assert_same original, ActiveRecord::Base.connection_handler
    end
  end

  def test_invalid_data_preserves_all_outputs_from_previous_generation
    with_dataset([ { "headline" => "Before" } ], columns: [ :headline ]) do |config, path|
      config.migrations_paths = [ File.expand_path("fixtures/migrations", __dir__) ]
      generator = RailsMigrations2sql::Generator.new(config)
      result = generator.generate(all: true, target: :postgresql)
      before = result.packages.to_h { |file| [ file, File.binread(file) ] }
      File.write(path, JSON.generate([ { "wrong" => "Missing headline" } ]))
      error = assert_raises(RailsMigrations2sql::OfflineCompilationError) { generator.generate(all: true, target: :postgresql) }
      assert_includes error.message, path
      assert_equal before, result.packages.to_h { |file| [ file, File.binread(file) ] }
    end
  end

  def test_disabling_seeds_does_not_evaluate_configured_sources
    with_dataset([]) do |config, _|
      config.migrations_paths = [ File.expand_path("fixtures/migrations", __dir__) ]
      config.seed_sources = [ { model: DatasetRecord, records: -> { raise "Seed must not run" } } ]
      result = RailsMigrations2sql::Generator.new(config).generate(all: true, target: :postgresql, seeds: false)
      assert_equal 2, result.migrations.length
      refute result.packages.any? { |file| file.end_with?("seed.sql") }
    end
  end

  def test_mappings_are_reloaded_and_symbol_attribute_hashes_are_supported
    with_dataset([ { "kind" => "news" } ], columns: { headline: { source: :kind, map: -> { { "news" => "News" } } } }) do |config, path|
      config.seed_sources << { model: DatasetRecord, records: -> { [ { headline: "Symbol" } ] }, columns: [ :headline ] }
      generator = RailsMigrations2sql::Generator.new(config)
      file = generator.generate_seeds(target: :postgresql).packages.first
      assert_includes File.read(file), "'News'"
      assert_includes File.read(file), "'Symbol'"
      File.write(path, JSON.generate([ { "kind" => "unknown" } ]))
      assert_raises(RailsMigrations2sql::OfflineCompilationError) { generator.generate_seeds(target: :postgresql) }
    end
  end

  def test_datetime_and_string_booleans_use_each_dialect
    with_dataset([ { "published_at" => "2026-09-28T08:00:00-04:00", "featured" => false } ],
                 types: { published_at: :datetime, featured: :oracle_boolean_string }) do |config, _|
      outputs = RailsMigrations2sql::Generator.new(config).generate_seeds(target: :all).packages.to_h do |file|
        [ File.basename(File.dirname(file)), File.read(file) ]
      end
      assert_includes outputs.fetch("oracle"), "TO_TIMESTAMP('2026-09-28 12:00:00.000000'"
      assert_includes outputs.fetch("oracle"), "'N'"
      assert_includes outputs.fetch("postgresql"), "TIMESTAMP '2026-09-28 12:00:00.000000', FALSE"
      assert_includes outputs.fetch("mysql"), "AS DATETIME(6))"
      assert_includes outputs.fetch("sqlserver"), "AS datetime2(6))"
    end
  end

  def test_invalid_booleans_are_rejected_instead_of_treating_strings_as_true
    with_dataset([ { "active" => "false" } ], types: { active: :numeric_boolean }) do |config, _|
      assert_raises(RailsMigrations2sql::OfflineCompilationError) { RailsMigrations2sql::Generator.new(config).generate_seeds(target: :postgresql) }
      assert_empty Dir[File.join(config.output_path, "**", "*.sql")]
    end
  end
end
