# frozen_string_literal: true

module RailsMigrations2sql
  class Configuration
    SUPPORTED_TARGETS = %i[postgresql mysql mariadb oracle sqlserver].freeze

    attr_accessor :target,
                  :output_path,
                  :migrations_paths,
                  :schema_path,
                  :use_schema_snapshot,
                  :strict,
                  :primary_key_type,
                  :schema_migrations_table_name

    def initialize
      @target = ENV.fetch("RAILS_DBA_TARGET", "postgresql").to_sym
      @output_path = nil
      @migrations_paths = nil
      @schema_path = nil
      @use_schema_snapshot = false
      @strict = true
      @primary_key_type = :bigint
      @schema_migrations_table_name = "schema_migrations"
    end

    def validate!
      targets = Array(target).map(&:to_sym)
      invalid = targets - SUPPORTED_TARGETS
      return if invalid.empty?

      raise ConfigurationError,
            "Unsupported target(s): #{invalid.join(', ')}. Supported: #{SUPPORTED_TARGETS.join(', ')}"
    end
  end
end
