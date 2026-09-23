# frozen_string_literal: true

module RailsMigrations2sql
  module Compilers
    class Base
      attr_reader :target, :warnings

      def initialize(target:, strict: true, primary_key_type: :bigint)
        @target = target.to_sym
        @strict = strict
        @primary_key_type = primary_key_type.to_sym
        @warnings = []
      end

      def compile(operations)
        Array(operations).flat_map { |operation| Array(compile_operation(operation)).flatten }.reject { |sql| sql.nil? || sql.empty? }
      end

      def compile_operation(operation)
        method = "compile_#{operation.name}"
        unless respond_to?(method, true)
          return unsupported!(operation.name, "No SQL compiler is implemented for #{operation.name}")
        end

        statements = send(method, operation)
        if operation.name == :change_column_null && operation.args[2] == false && !operation.args[3].nil?
          table, column, _, default = operation.args
          update = "UPDATE #{quote_table(table)} SET #{quote_column(column)} = #{literal(default)} WHERE #{quote_column(column)} IS NULL"
          [update, *Array(statements)]
        else
          statements
        end
      end

      def quote_table(name)
        name.to_s.split(".").map { |part| quote_identifier(part) }.join(".")
      end

      def quote_column(name)
        quote_identifier(name)
      end

      def quote_identifier(name)
        %Q{"#{name.to_s.gsub('"', '""')}"}
      end

      def literal(value)
        case value
        when nil then "NULL"
        when true then boolean_literal(true)
        when false then boolean_literal(false)
        when Numeric then value.to_s
        when Symbol then literal(value.to_s)
        when String then "'#{value.gsub("'", "''")}'"
        when Proc
          expression = value.call
          expression.to_s
        else
          if value.respond_to?(:iso8601)
            literal(value.iso8601)
          else
            literal(value.to_s)
          end
        end
      end

      def boolean_literal(value)
        value ? "TRUE" : "FALSE"
      end

      protected

      def compile_create_table(op)
        table = op.args[0]
        options = op.options
        data = op.data || {}
        columns = Array(data[:columns]).dup

        unless options[:id] == false || options[:primary_key].is_a?(Array) || columns.any? { |column| column.dig(:options, :primary_key) }
          id_name = options[:primary_key] || "id"
          id_type = options[:id].is_a?(Symbol) ? options[:id] : @primary_key_type
          columns.unshift(name: id_name.to_s, type: id_type, options: { primary_key: true, auto_increment: %i[primary_key integer bigint].include?(id_type.to_sym) })
        end

        definitions = columns.map { |column| column_definition(column[:name], column[:type], column[:options] || {}) }
        if options[:primary_key].is_a?(Array)
          definitions << "PRIMARY KEY (#{options[:primary_key].map { |name| quote_column(name) }.join(', ')})"
        end

        create = "CREATE TABLE #{quote_table(table)} (\n  #{definitions.join(",\n  ")}\n)"
        create += " #{options[:options]}" if options[:options]

        statements = [create]
        Array(data[:indexes]).each do |index|
          statements.concat(Array(compile_add_index(Operation.new(name: :add_index, args: [table, index[:columns]], options: index[:options] || {}))))
        end
        Array(data[:foreign_keys]).each do |fk|
          statements.concat(Array(compile_add_foreign_key(Operation.new(name: :add_foreign_key, args: [table, fk[:to_table]], options: fk[:options] || {}))))
        end
        statements
      end

      def compile_drop_table(op)
        op.args.map do |table|
          clause = op.options[:if_exists] ? " IF EXISTS" : ""
          "DROP TABLE#{clause} #{quote_table(table)}#{cascade_clause(op.options)}"
        end
      end

      def compile_create_join_table(op)
        table = op.options[:table_name] || op.args.map(&:to_s).sort.join("_")
        compile_create_table(Operation.new(name: :create_table, args: [table], options: op.options.merge(id: false), data: op.data))
      end

      def compile_drop_join_table(op)
        table = op.options[:table_name] || op.args.map(&:to_s).sort.join("_")
        compile_drop_table(Operation.new(name: :drop_table, args: [table], options: op.options))
      end

      def compile_rename_table(op)
        "ALTER TABLE #{quote_table(op.args[0])} RENAME TO #{quote_table(op.args[1])}"
      end

      def compile_add_column(op)
        "ALTER TABLE #{quote_table(op.args[0])} ADD #{column_definition(op.args[1], op.args[2], op.options)}"
      end

      def compile_remove_column(op)
        "ALTER TABLE #{quote_table(op.args[0])} DROP COLUMN #{quote_column(op.args[1])}"
      end

      def compile_remove_columns(op)
        op.args.drop(1).flat_map do |column|
          Array(compile_remove_column(Operation.new(name: :remove_column, args: [op.args[0], column], options: op.options)))
        end
      end

      def compile_rename_column(op)
        "ALTER TABLE #{quote_table(op.args[0])} RENAME COLUMN #{quote_column(op.args[1])} TO #{quote_column(op.args[2])}"
      end

      def compile_change_column(op)
        unsupported!(op.name, "#{target} must implement change_column")
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
        null = op.args[2]
        action = null ? "DROP NOT NULL" : "SET NOT NULL"
        "ALTER TABLE #{quote_table(op.args[0])} ALTER COLUMN #{quote_column(op.args[1])} #{action}"
      end

      def compile_add_index(op)
        table, columns = op.args.first(2)
        opts = op.options
        name = opts[:name] || Util.default_index_name(table, columns)
        unique = opts[:unique] ? "UNIQUE " : ""
        using = opts[:using] ? " USING #{opts[:using]}" : ""
        concurrently = opts[:algorithm].to_s == "concurrently" ? " CONCURRENTLY" : ""
        column_sql = index_columns(columns, opts)
        sql = "CREATE #{unique}INDEX#{concurrently} #{quote_identifier(name)} ON #{quote_table(table)}#{using} (#{column_sql})"
        sql += " WHERE #{opts[:where]}" if opts[:where]
        sql
      end

      def compile_remove_index(op)
        table, columns = op.args.first(2)
        name = op.options[:name] || Util.default_index_name(table, columns)
        "DROP INDEX #{quote_identifier(name)}"
      end

      def compile_rename_index(op)
        "ALTER INDEX #{quote_identifier(op.args[1])} RENAME TO #{quote_identifier(op.args[2])}"
      end

      def compile_add_reference(op)
        table, ref = op.args.first(2)
        opts = op.options
        type = (opts[:type] || :bigint).to_sym
        column_opts = opts.reject { |key, _| %i[type polymorphic index foreign_key].include?(key) }
        statements = []
        if opts[:polymorphic]
          statements << compile_add_column(Operation.new(name: :add_column, args: [table, "#{ref}_type", :string], options: column_opts))
        end
        statements << compile_add_column(Operation.new(name: :add_column, args: [table, "#{ref}_id", type], options: column_opts))

        unless opts[:index] == false
          columns = opts[:polymorphic] ? ["#{ref}_type", "#{ref}_id"] : ["#{ref}_id"]
          idx_opts = normalize_index_options(opts[:index])
          statements << compile_add_index(Operation.new(name: :add_index, args: [table, columns], options: idx_opts))
        end

        if opts[:foreign_key]
          fk_opts = opts[:foreign_key].is_a?(Hash) ? opts[:foreign_key].dup : {}
          to_table = fk_opts.delete(:to_table) || Util.pluralize(ref)
          fk_opts[:column] ||= "#{ref}_id"
          statements << compile_add_foreign_key(Operation.new(name: :add_foreign_key, args: [table, to_table], options: fk_opts))
        end
        statements.flatten
      end

      def compile_remove_reference(op)
        table, ref = op.args.first(2)
        opts = op.options
        statements = []
        if opts[:foreign_key]
          fk_opts = opts[:foreign_key].is_a?(Hash) ? opts[:foreign_key].dup : {}
          to_table = fk_opts.delete(:to_table) || Util.pluralize(ref)
          fk_opts[:column] ||= "#{ref}_id"
          statements << compile_remove_foreign_key(Operation.new(name: :remove_foreign_key, args: [table, to_table], options: fk_opts))
        end
        unless opts[:index] == false
          columns = opts[:polymorphic] ? ["#{ref}_type", "#{ref}_id"] : ["#{ref}_id"]
          idx_opts = normalize_index_options(opts[:index])
          statements << compile_remove_index(Operation.new(name: :remove_index, args: [table, columns], options: idx_opts))
        end
        statements << compile_remove_column(Operation.new(name: :remove_column, args: [table, "#{ref}_id"]))
        statements << compile_remove_column(Operation.new(name: :remove_column, args: [table, "#{ref}_type"])) if opts[:polymorphic]
        statements.flatten
      end

      def compile_add_foreign_key(op)
        from_table, to_table = op.args.first(2)
        opts = op.options
        column = opts[:column] || "#{Util.singularize(to_table)}_id"
        primary_key = opts[:primary_key] || "id"
        name = opts[:name] || Util.default_foreign_key_name(from_table, column)
        sql = "ALTER TABLE #{quote_table(from_table)} ADD CONSTRAINT #{quote_identifier(name)} FOREIGN KEY (#{Array(column).map { |c| quote_column(c) }.join(', ')}) REFERENCES #{quote_table(to_table)} (#{Array(primary_key).map { |c| quote_column(c) }.join(', ')})"
        sql += " ON DELETE #{referential_action(opts[:on_delete])}" if opts[:on_delete]
        sql += " ON UPDATE #{referential_action(opts[:on_update])}" if opts[:on_update]
        sql += " DEFERRABLE#{opts[:deferrable] == :deferred ? ' INITIALLY DEFERRED' : ''}" if opts[:deferrable]
        sql
      end

      def compile_remove_foreign_key(op)
        from_table, to_table = op.args.first(2)
        opts = op.options
        column = opts[:column] || (to_table && "#{Util.singularize(to_table)}_id")
        name = opts[:name] || (column && Util.default_foreign_key_name(from_table, column))
        raise UnsupportedOperationError, "remove_foreign_key requires name:, column:, or to_table offline" unless name

        "ALTER TABLE #{quote_table(from_table)} #{drop_foreign_key_clause} #{quote_identifier(name)}"
      end

      def drop_foreign_key_clause
        "DROP CONSTRAINT"
      end

      def compile_add_check_constraint(op)
        table, expression = op.args.first(2)
        name = op.options[:name] || "chk_rails_#{Digest::SHA256.hexdigest("#{table}_#{expression}_chk")[0, 10]}"
        sql = "ALTER TABLE #{quote_table(table)} ADD CONSTRAINT #{quote_identifier(name)} CHECK (#{expression})"
        sql += " NOT VALID" if op.options[:validate] == false && target == :postgresql
        sql
      end

      def compile_remove_check_constraint(op)
        table, expression = op.args.first(2)
        name = op.options[:name] || (expression && "chk_rails_#{Digest::SHA256.hexdigest("#{table}_#{expression}_chk")[0, 10]}")
        raise UnsupportedOperationError, "remove_check_constraint requires name: or expression offline" unless name

        "ALTER TABLE #{quote_table(table)} DROP CONSTRAINT #{quote_identifier(name)}"
      end

      def compile_add_timestamps(op)
        options = { null: false }.merge(op.options)
        [
          compile_add_column(Operation.new(name: :add_column, args: [op.args[0], :created_at, :datetime], options: options)),
          compile_add_column(Operation.new(name: :add_column, args: [op.args[0], :updated_at, :datetime], options: options))
        ]
      end

      def compile_remove_timestamps(op)
        [
          compile_remove_column(Operation.new(name: :remove_column, args: [op.args[0], :updated_at])),
          compile_remove_column(Operation.new(name: :remove_column, args: [op.args[0], :created_at]))
        ]
      end

      def compile_execute(op)
        op.args[0].to_s.strip.sub(/;\s*\z/, "")
      end

      def compile_enable_extension(op)
        unsupported!(op.name, "Extensions are database-specific and #{target} has no implementation")
      end

      def compile_disable_extension(op)
        unsupported!(op.name, "Extensions are database-specific and #{target} has no implementation")
      end

      def compile_change_table_comment(op)
        unsupported!(op.name, "Table comments are not implemented for #{target}")
      end

      def compile_change_column_comment(op)
        unsupported!(op.name, "Column comments are not implemented for #{target}")
      end

      def column_definition(name, type, options = {})
        sql_type = type_sql(type, options)
        chunks = [quote_column(name), sql_type]
        chunks << auto_increment_clause(type, options) if options[:auto_increment]
        chunks << generated_clause(options) if options[:as]
        chunks << "DEFAULT #{literal(options[:default])}" if options.key?(:default) && !options[:default].nil?
        chunks << "NOT NULL" if options[:null] == false
        chunks << "NULL" if options[:null] == true && explicit_null_clause?
        chunks << "PRIMARY KEY" if options[:primary_key]
        chunks.compact.reject(&:empty?).join(" ")
      end

      def type_sql(type, options = {})
        type = type.to_sym
        limit = options[:limit]
        precision = options[:precision]
        scale = options[:scale]
        case type
        when :primary_key then type_sql(@primary_key_type, options)
        when :string then "varchar(#{limit || 255})"
        when :text then "text"
        when :integer then "integer"
        when :bigint then "bigint"
        when :float then "double precision"
        when :decimal, :numeric
          precision ? "decimal(#{precision}#{scale.nil? ? '' : ",#{scale}"})" : "decimal"
        when :boolean then "boolean"
        when :date then "date"
        when :datetime, :timestamp then precision ? "timestamp(#{precision})" : "timestamp"
        when :time then precision ? "time(#{precision})" : "time"
        when :binary then "blob"
        when :json then "json"
        when :jsonb then "jsonb"
        when :uuid then "uuid"
        when :inet then "inet"
        when :interval then "interval"
        when :virtual
          actual = options[:type]
          raise UnsupportedOperationError, "virtual column requires type:" unless actual
          type_sql(actual, options)
        else
          type.to_s
        end
      end

      def auto_increment_clause(_type, _options)
        nil
      end

      def generated_clause(options)
        "GENERATED ALWAYS AS (#{options[:as]})#{options[:stored] ? ' STORED' : ''}"
      end

      def explicit_null_clause?
        false
      end

      def cascade_clause(options)
        options[:force] == :cascade ? " CASCADE" : ""
      end

      def index_columns(columns, opts)
        order = opts[:order] || {}
        Array(columns).map do |column|
          name = column.to_s
          direction = order.is_a?(Hash) ? (order[column.to_sym] || order[name]) : order
          [quote_column(name), direction&.to_s&.upcase].compact.join(" ")
        end.join(", ")
      end

      def normalize_index_options(value)
        case value
        when Hash then value
        when String, Symbol then { name: value.to_s }
        else {}
        end
      end

      def change_to_value(value)
        if value.is_a?(Hash) && (value.key?(:to) || value.key?("to"))
          Util.change_value(value, :to)
        else
          value
        end
      end

      def referential_action(action)
        case action.to_sym
        when :cascade then "CASCADE"
        when :nullify then "SET NULL"
        when :restrict then "RESTRICT"
        else action.to_s.tr("_", " ").upcase
        end
      end

      def unsupported!(operation, message)
        raise UnsupportedOperationError, message if @strict

        @warnings << "#{operation}: #{message}"
        "-- UNSUPPORTED: #{message}"
      end
    end
  end
end
