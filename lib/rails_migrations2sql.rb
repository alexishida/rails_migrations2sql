# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/inflector"

require_relative "rails_migrations2sql/version"
require_relative "rails_migrations2sql/errors"
require_relative "rails_migrations2sql/configuration"
require_relative "rails_migrations2sql/util"
require_relative "rails_migrations2sql/operation"
require_relative "rails_migrations2sql/virtual_schema"
require_relative "rails_migrations2sql/table_definition"
require_relative "rails_migrations2sql/inverter"
require_relative "rails_migrations2sql/recorder"
require_relative "rails_migrations2sql/offline_connection"
require_relative "rails_migrations2sql/offline_guard"
require_relative "rails_migrations2sql/migration_sandbox"
require_relative "rails_migrations2sql/compilers/base"
require_relative "rails_migrations2sql/compilers/postgresql"
require_relative "rails_migrations2sql/compilers/mysql"
require_relative "rails_migrations2sql/compilers/oracle"
require_relative "rails_migrations2sql/compilers/sqlserver"
require_relative "rails_migrations2sql/compiler_factory"
require_relative "rails_migrations2sql/migration_file"
require_relative "rails_migrations2sql/migration_discovery"
require_relative "rails_migrations2sql/migration_loader"
require_relative "rails_migrations2sql/schema_loader"
require_relative "rails_migrations2sql/migration_evaluator"
require_relative "rails_migrations2sql/sql_formatter"
require_relative "rails_migrations2sql/package_writer"
require_relative "rails_migrations2sql/seed_recorder"
require_relative "rails_migrations2sql/generator"

module RailsMigrations2sql
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def generate(**options)
      Generator.new(configuration).generate(**options)
    end

    def generate_seeds(**options)
      Generator.new(configuration).generate_seeds(**options)
    end
  end
end

require_relative "rails_migrations2sql/railtie" if defined?(Rails::Railtie)
