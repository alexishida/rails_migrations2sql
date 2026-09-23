# frozen_string_literal: true

module RailsMigrations2sql
  class Configuration
    SUPPORTED_TARGETS = %i[postgresql mysql mariadb oracle sqlserver].freeze
    ADAPTER_TARGETS = {
      "postgresql" => :postgresql,
      "mysql2" => :mysql,
      "trilogy" => :mysql,
      "mysql" => :mysql,
      "mariadb" => :mariadb,
      "oracle_enhanced" => :oracle,
      "oracle" => :oracle,
      "sqlserver" => :sqlserver
    }.freeze

    attr_writer :target
    attr_accessor :output_path,
                  :migrations_paths,
                  :schema_path,
                  :use_schema_snapshot,
                  :strict,
                  :primary_key_type,
                  :schema_migrations_table_name

    def initialize
      @target = :auto
      @output_path = nil
      @migrations_paths = nil
      @schema_path = nil
      @use_schema_snapshot = false
      @strict = true
      @primary_key_type = :bigint
      @schema_migrations_table_name = "schema_migrations"
    end

    def target
      configured = @target
      configured = ENV.fetch("RAILS_DBA_TARGET", "auto").to_sym if configured.nil? || configured.to_s == "auto"
      configured.to_s == "auto" ? detected_target : configured
    end

    def validate!
      targets = Array(target).map(&:to_sym)
      invalid = targets - SUPPORTED_TARGETS
      return if invalid.empty?

      raise ConfigurationError,
            "Unsupported target(s): #{invalid.join(', ')}. Supported: #{SUPPORTED_TARGETS.join(', ')}"
    end

    private

    def detected_target
      environment = ActiveRecord::ConnectionHandling::DEFAULT_ENV.call.to_s
      configurations = ActiveRecord::Base.configurations
      database = configurations.configs_for(env_name: environment, name: "primary", include_hidden: true) ||
                 configurations.configs_for(env_name: environment).first

      unless database
        raise ConfigurationError,
              "No database configuration found for #{environment}; configure the Rails database or set config.target / TARGET explicitly"
      end

      ADAPTER_TARGETS.fetch(database.adapter.to_s) do
        raise ConfigurationError,
              "Unsupported database adapter #{database.adapter.inspect} for #{environment}; " \
              "set config.target / TARGET to one of: #{SUPPORTED_TARGETS.join(', ')}"
      end
    end
  end
end
