# frozen_string_literal: true

module RailsMigrations2sql
  module CompilerFactory
    module_function

    def build(target, configuration = RailsMigrations2sql.configuration)
      options = { strict: configuration.strict, primary_key_type: configuration.primary_key_type }
      case target.to_sym
      when :postgresql then Compilers::PostgreSQL.new(**options)
      when :mysql then Compilers::MySQL.new(**options)
      when :mariadb then Compilers::MariaDB.new(**options)
      when :oracle then Compilers::Oracle.new(**options)
      when :sqlserver then Compilers::SQLServer.new(**options)
      else
        raise ConfigurationError, "Unsupported target: #{target}"
      end
    end
  end
end
