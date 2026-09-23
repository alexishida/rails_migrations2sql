# frozen_string_literal: true

module RailsMigrations2sql
  module Compilers
    class SQLServer < Base
      def initialize(**options)
        super(target: :sqlserver, **options)
      end

      def quote_identifier(name)
        "[#{name.to_s.gsub(']', ']]')}]"
      end

      def boolean_literal(value)
        value ? "1" : "0"
      end

      protected

      def type_sql(type, options = {})
        case type.to_sym
        when :string then "nvarchar(#{options[:limit] || 255})"
        when :text then "nvarchar(max)"
        when :integer then "int"
        when :bigint then "bigint"
        when :float then "float"
        when :decimal, :numeric
          options[:precision] ? "decimal(#{options[:precision]}#{options[:scale].nil? ? '' : ",#{options[:scale]}"})" : "decimal(18,0)"
        when :boolean then "bit"
        when :date then "date"
        when :datetime, :timestamp then "datetime2#{options[:precision] ? "(#{options[:precision]})" : ''}"
        when :time then "time#{options[:precision] ? "(#{options[:precision]})" : ''}"
        when :binary then "varbinary(max)"
        when :json, :jsonb then "nvarchar(max)"
        when :uuid then "uniqueidentifier"
        when :inet then "nvarchar(45)"
        else super
        end
      end

      def auto_increment_clause(_type, options)
        options[:primary_key] ? "IDENTITY(1,1)" : nil
      end

      def explicit_null_clause?
        true
      end

      def compile_rename_table(op)
        "EXEC sp_rename #{literal(op.args[0].to_s)}, #{literal(op.args[1].to_s)}"
      end

      def compile_rename_column(op)
        "EXEC sp_rename #{literal("#{op.args[0]}.#{op.args[1]}")}, #{literal(op.args[2].to_s)}, 'COLUMN'"
      end

      def compile_remove_column(op)
        table, column = op.args.first(2)
        drop_default = drop_default_constraint_sql(table, column)
        [drop_default, "ALTER TABLE #{quote_table(table)} DROP COLUMN #{quote_column(column)}"]
      end

      def compile_change_column(op)
        table, column, type = op.args.first(3)
        opts = op.options
        null_clause = if opts.key?(:null)
                        opts[:null] ? " NULL" : " NOT NULL"
                      else
                        ""
                      end
        statements = ["ALTER TABLE #{quote_table(table)} ALTER COLUMN #{quote_column(column)} #{type_sql(type, opts)}#{null_clause}"]
        if opts.key?(:default)
          statements << compile_change_column_default(Operation.new(name: :change_column_default, args: [table, column, opts[:default]]))
        end
        statements
      end

      def compile_change_column_default(op)
        table, column = op.args.first(2)
        value = change_to_value(op.args[2])
        drop = drop_default_constraint_sql(table, column)
        return drop if value.nil?

        constraint = "DF_#{table}_#{column}"
        "#{drop}\nALTER TABLE #{quote_table(table)} ADD CONSTRAINT #{quote_identifier(constraint)} DEFAULT #{literal(value)} FOR #{quote_column(column)}"
      end

      def compile_change_column_null(op)
        type = op.options[:current_type]
        current_options = op.options[:current_options] || {}
        return unsupported!(op.name, "SQL Server change_column_null needs the current column type; enable a schema snapshot or supply a prior create/add operation") unless type

        null_clause = op.args[2] ? "NULL" : "NOT NULL"
        "ALTER TABLE #{quote_table(op.args[0])} ALTER COLUMN #{quote_column(op.args[1])} #{type_sql(type, current_options)} #{null_clause}"
      end

      def compile_remove_index(op)
        table, columns = op.args.first(2)
        name = op.options[:name] || Util.default_index_name(table, columns)
        "DROP INDEX #{quote_identifier(name)} ON #{quote_table(table)}"
      end

      def compile_rename_index(op)
        "EXEC sp_rename #{literal("#{op.args[0]}.#{op.args[1]}")}, #{literal(op.args[2].to_s)}, 'INDEX'"
      end

      def compile_add_foreign_key(op)
        return unsupported!(op.name, "SQL Server foreign keys are not DEFERRABLE") if op.options[:deferrable]
        super
      end

      def referential_action(action)
        return "NO ACTION" if action.to_sym == :restrict
        super
      end

      def drop_default_constraint_sql(table, column)
        batch = <<~SQL.strip
          DECLARE @df sysname;
          SELECT @df = dc.name
          FROM sys.default_constraints dc
          JOIN sys.columns c ON c.default_object_id = dc.object_id
          WHERE dc.parent_object_id = OBJECT_ID(N'#{table.to_s.gsub("'", "''")}')
            AND c.name = N'#{column.to_s.gsub("'", "''")}';
          IF @df IS NOT NULL
          BEGIN
            DECLARE @sql nvarchar(max);
            SET @sql = N#{literal("ALTER TABLE #{quote_table(table)} DROP CONSTRAINT ")} + QUOTENAME(@df);
            EXEC sys.sp_executesql @sql;
          END;
        SQL
        "EXEC sys.sp_executesql N#{literal(batch)};"
      end
    end
  end
end
