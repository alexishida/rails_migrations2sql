# frozen_string_literal: true

module RailsMigrations2sql
  module Compilers
    class MySQL < Base
      def initialize(target: :mysql, **options)
        super(target: target, **options)
      end

      def quote_identifier(name)
        "`#{name.to_s.gsub('`', '``')}`"
      end

      def boolean_literal(value)
        value ? "1" : "0"
      end

      protected

      def type_sql(type, options = {})
        case type.to_sym
        when :string then "varchar(#{options[:limit] || 255})"
        when :text then "text"
        when :integer then integer_sql(options[:limit])
        when :bigint then "bigint"
        when :float then "double"
        when :boolean then "tinyint(1)"
        when :datetime then options[:precision] ? "datetime(#{options[:precision]})" : "datetime"
        when :timestamp then options[:precision] ? "timestamp(#{options[:precision]})" : "timestamp"
        when :binary then "blob"
        when :json, :jsonb then "json"
        when :uuid then "char(36)"
        when :inet then "varchar(45)"
        else super
        end
      end

      def auto_increment_clause(_type, options)
        options[:primary_key] ? "AUTO_INCREMENT" : nil
      end

      def explicit_null_clause?
        true
      end

      def compile_rename_table(op)
        "RENAME TABLE #{quote_table(op.args[0])} TO #{quote_table(op.args[1])}"
      end

      def compile_change_column(op)
        table, column, type = op.args.first(3)
        "ALTER TABLE #{quote_table(table)} MODIFY COLUMN #{column_definition(column, type, op.options)}"
      end

      def compile_change_column_default(op)
        value = change_to_value(op.args[2])
        if value.nil?
          "ALTER TABLE #{quote_table(op.args[0])} ALTER COLUMN #{quote_column(op.args[1])} DROP DEFAULT"
        else
          "ALTER TABLE #{quote_table(op.args[0])} ALTER COLUMN #{quote_column(op.args[1])} SET DEFAULT #{literal(value)}"
        end
      end

      def compile_change_column_null(op)
        type = op.options[:current_type]
        current_options = op.options[:current_options] || {}
        return unsupported!(op.name, "MySQL/MariaDB change_column_null needs the current column type; enable a schema snapshot or supply a prior create/add operation") unless type

        options = current_options.merge(null: op.args[2])
        "ALTER TABLE #{quote_table(op.args[0])} MODIFY COLUMN #{column_definition(op.args[1], type, options)}"
      end

      def compile_remove_index(op)
        table, columns = op.args.first(2)
        name = op.options[:name] || Util.default_index_name(table, columns)
        "DROP INDEX #{quote_identifier(name)} ON #{quote_table(table)}"
      end

      def compile_rename_index(op)
        "ALTER TABLE #{quote_table(op.args[0])} RENAME INDEX #{quote_identifier(op.args[1])} TO #{quote_identifier(op.args[2])}"
      end

      def compile_add_index(op)
        if op.options[:where]
          return unsupported!(op.name, "MySQL/MariaDB does not support Rails-style partial indexes with where:")
        end

        table, columns = op.args.first(2)
        opts = op.options
        name = opts[:name] || Util.default_index_name(table, columns)
        unique = opts[:unique] ? "UNIQUE " : ""
        using = opts[:using] ? " USING #{opts[:using].to_s.upcase}" : ""
        sql = "CREATE #{unique}INDEX #{quote_identifier(name)}#{using} ON #{quote_table(table)} (#{index_columns(columns, opts)})"
        sql += " ALGORITHM=#{opts[:algorithm].to_s.upcase}" if opts[:algorithm] && opts[:algorithm].to_s != "default"
        sql
      end

      def compile_add_foreign_key(op)
        opts = op.options
        if opts[:deferrable]
          return unsupported!(op.name, "MySQL/MariaDB foreign keys are not DEFERRABLE")
        end
        super
      end

      private

      def integer_sql(limit)
        case limit.to_i
        when 1 then "tinyint"
        when 2 then "smallint"
        when 3 then "mediumint"
        when 8 then "bigint"
        else "int"
        end
      end
    end

    class MariaDB < MySQL
      def initialize(**options)
        super(target: :mariadb, **options)
      end
    end
  end
end
