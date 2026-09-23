# frozen_string_literal: true

RailsMigrations2sql.configure do |config|
  # Detect the primary database adapter for the current Rails environment.
  # No database connection is opened. RAILS_DBA_TARGET overrides auto detection.
  # Or set :postgresql, :mysql, :mariadb, :oracle or :sqlserver explicitly.
  config.target = :auto

  # Default: Rails.root.join("db", "sql")
  # config.output_path = Rails.root.join("db", "sql")

  # Strict mode aborts instead of emitting guessed SQL for unsupported operations.
  config.strict = true

  # Optional. If enabled, db/schema.rb seeds an in-memory schema used only for
  # predicates such as column_exists? and for operations that need the current type.
  # No schema SQL is executed.
  config.use_schema_snapshot = false
  # config.schema_path = Rails.root.join("db", "schema.rb")

  config.primary_key_type = :bigint
  config.schema_migrations_table_name = "schema_migrations"
end
