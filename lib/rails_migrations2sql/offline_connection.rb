# frozen_string_literal: true

module RailsMigrations2sql
  class OfflineConnection
    ADAPTER_NAMES = {
      postgresql: "PostgreSQL",
      mysql: "Mysql2",
      mariadb: "Mysql2",
      oracle: "OracleEnhanced",
      sqlserver: "SQLServer"
    }.freeze

    def initialize(recorder:, compiler:)
      @recorder = recorder
      @compiler = compiler
    end

    def adapter_name
      ADAPTER_NAMES.fetch(@compiler.target)
    end

    def quote(value)
      @compiler.literal(value)
    end

    def quote_table_name(value)
      @compiler.quote_table(value)
    end

    def quote_column_name(value)
      @compiler.quote_column(value)
    end

    def execute(sql, *_args, **_kwargs)
      @recorder.record(Operation.new(name: :execute, args: [sql.to_s]))
    end

    def table_exists?(name)
      @recorder.schema.table_exists?(name)
    end

    def column_exists?(table, column, type = nil, **options)
      @recorder.schema.column_exists?(table, column, type, **options)
    end

    def index_exists?(table, columns = nil, **options)
      @recorder.schema.index_exists?(table, columns, **options)
    end

    def foreign_key_exists?(from_table, to_table = nil, **options)
      @recorder.schema.foreign_key_exists?(from_table, to_table, **options)
    end

    def method_missing(name, *_args, **_kwargs, &_block)
      raise UnsupportedOperationError,
            "connection.#{name} requires a real database connection and cannot be compiled offline; " \
            "use execute with SQL reviewed by the DBA"
    end

    def respond_to_missing?(_name, _include_private = false)
      false
    end
  end
end
