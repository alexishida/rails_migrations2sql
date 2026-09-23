# frozen_string_literal: true

RailsMigrations2sql.configure do |config|
  # SQL dialect to generate: :postgresql, :mysql, :mariadb, :oracle or :sqlserver.
  config.target = :postgresql

  # Default: Rails.root.join("db", "dba_migrations")
  # config.output_path = Rails.root.join("db", "dba_migrations")

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
