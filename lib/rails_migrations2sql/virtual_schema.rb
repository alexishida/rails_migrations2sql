# frozen_string_literal: true

module RailsMigrations2sql
  class VirtualSchema
    Column = Struct.new(:name, :type, :options, keyword_init: true)
    Index = Struct.new(:name, :columns, :options, keyword_init: true)
    ForeignKey = Struct.new(:name, :to_table, :column, :primary_key, :options, keyword_init: true)
    Table = Struct.new(:name, :columns, :indexes, :foreign_keys, :known, keyword_init: true)

    def initialize
      @tables = {}
    end

    def initialize_copy(other)
      super
      @tables = Marshal.load(Marshal.dump(other.instance_variable_get(:@tables)))
    end

    def create_table(name, columns: [], indexes: [], foreign_keys: [])
      table = Table.new(name: name.to_s, columns: {}, indexes: {}, foreign_keys: {}, known: true)
      columns.each { |column| table.columns[column[:name].to_s] = Column.new(name: column[:name].to_s, type: column[:type]&.to_sym, options: column[:options] || {}) }
      indexes.each do |index|
        iname = index[:options]&.dig(:name) || Util.default_index_name(name, index[:columns])
        table.indexes[iname.to_s] = Index.new(name: iname.to_s, columns: Array(index[:columns]).map(&:to_s), options: index[:options] || {})
      end
      foreign_keys.each do |fk|
        column = fk[:options]&.dig(:column) || "#{fk[:to_table].to_s.sub(/s\z/, '')}_id"
        fname = fk[:options]&.dig(:name) || Util.default_foreign_key_name(name, column)
        table.foreign_keys[fname.to_s] = ForeignKey.new(name: fname.to_s, to_table: fk[:to_table].to_s, column: column.to_s, primary_key: (fk[:options]&.dig(:primary_key) || "id").to_s, options: fk[:options] || {})
      end
      @tables[name.to_s] = table
    end

    def ensure_table(name)
      @tables[name.to_s] ||= Table.new(name: name.to_s, columns: {}, indexes: {}, foreign_keys: {}, known: false)
    end

    def drop_table(name)
      @tables.delete(name.to_s)
    end

    def rename_table(old_name, new_name)
      table = require_known_table!(old_name)
      @tables.delete(old_name.to_s)
      table.name = new_name.to_s
      @tables[new_name.to_s] = table
    end

    def add_column(table_name, column_name, type, options = {})
      table = ensure_table(table_name)
      table.columns[column_name.to_s] = Column.new(name: column_name.to_s, type: type&.to_sym, options: options || {})
    end

    def remove_column(table_name, column_name)
      table = require_known_table!(table_name)
      table.columns.delete(column_name.to_s)
    end

    def rename_column(table_name, old_name, new_name)
      table = require_known_table!(table_name)
      column = table.columns.delete(old_name.to_s)
      raise UnknownSchemaStateError, "Unknown column #{table_name}.#{old_name}" unless column

      column.name = new_name.to_s
      table.columns[new_name.to_s] = column
    end

    def change_column(table_name, column_name, type = nil, options = {})
      table = require_known_table!(table_name)
      column = table.columns[column_name.to_s]
      raise UnknownSchemaStateError, "Unknown column #{table_name}.#{column_name}" unless column

      column.type = type.to_sym if type
      column.options = column.options.merge(options || {})
    end

    def add_index(table_name, columns, options = {})
      table = ensure_table(table_name)
      name = options[:name] || Util.default_index_name(table_name, columns)
      table.indexes[name.to_s] = Index.new(name: name.to_s, columns: Array(columns).map(&:to_s), options: options)
    end

    def remove_index(table_name, columns = nil, options = {})
      table = require_known_table!(table_name)
      name = options[:name] || (columns && Util.default_index_name(table_name, columns))
      if name
        table.indexes.delete(name.to_s)
      elsif columns
        wanted = Array(columns).map(&:to_s)
        key = table.indexes.find { |_k, idx| idx.columns == wanted }&.first
        table.indexes.delete(key) if key
      end
    end

    def rename_index(table_name, old_name, new_name)
      table = require_known_table!(table_name)
      index = table.indexes.delete(old_name.to_s)
      return unless index

      index.name = new_name.to_s
      table.indexes[new_name.to_s] = index
    end

    def add_foreign_key(from_table, to_table, options = {})
      table = ensure_table(from_table)
      column = options[:column] || "#{to_table.to_s.sub(/s\z/, '')}_id"
      name = options[:name] || Util.default_foreign_key_name(from_table, column)
      table.foreign_keys[name.to_s] = ForeignKey.new(
        name: name.to_s,
        to_table: to_table.to_s,
        column: column.to_s,
        primary_key: (options[:primary_key] || "id").to_s,
        options: options
      )
    end

    def remove_foreign_key(from_table, to_table = nil, options = {})
      table = require_known_table!(from_table)
      name = options[:name]
      if name
        table.foreign_keys.delete(name.to_s)
      else
        column = options[:column]
        pair = table.foreign_keys.find do |_key, fk|
          (!to_table || fk.to_table == to_table.to_s) && (!column || fk.column == column.to_s)
        end
        table.foreign_keys.delete(pair.first) if pair
      end
    end

    def table_exists?(name)
      table = @tables[name.to_s]
      raise UnknownSchemaStateError, "Schema state for table #{name} is unknown" unless table

      true
    end

    def column_exists?(table_name, column_name, type = nil, **options)
      table = require_known_table!(table_name)
      column = table.columns[column_name.to_s]
      return false unless column
      return false if type && column.type != type.to_sym
      options.all? { |key, value| column.options[key] == value }
    end

    def index_exists?(table_name, columns = nil, **options)
      table = require_known_table!(table_name)
      name = options[:name]
      return table.indexes.key?(name.to_s) if name

      wanted = Array(columns).map(&:to_s)
      table.indexes.values.any? { |index| index.columns == wanted }
    end

    def foreign_key_exists?(from_table, to_table = nil, **options)
      table = require_known_table!(from_table)
      table.foreign_keys.values.any? do |fk|
        (!to_table || fk.to_table == to_table.to_s) &&
          (!options[:column] || fk.column == options[:column].to_s) &&
          (!options[:name] || fk.name == options[:name].to_s)
      end
    end

    def column(table_name, column_name)
      table = @tables[table_name.to_s]
      return nil unless table&.known

      table.columns[column_name.to_s]
    end

    def apply(operation)
      case operation.name
      when :create_table
        data = operation.data || {}
        create_table(operation.args[0], columns: data[:columns] || [], indexes: data[:indexes] || [], foreign_keys: data[:foreign_keys] || [])
      when :drop_table
        drop_table(operation.args[0])
      when :rename_table
        rename_table(*operation.args.first(2))
      when :add_column
        add_column(operation.args[0], operation.args[1], operation.args[2], operation.options)
      when :remove_column
        remove_column(operation.args[0], operation.args[1])
      when :rename_column
        rename_column(*operation.args.first(3))
      when :change_column
        change_column(operation.args[0], operation.args[1], operation.args[2], operation.options)
      when :change_column_default
        changes = operation.args[2]
        value = changes.is_a?(Hash) ? (changes[:to] || changes["to"]) : changes
        change_column(operation.args[0], operation.args[1], nil, default: value)
      when :change_column_null
        change_column(operation.args[0], operation.args[1], nil, null: operation.args[2])
      when :add_index
        add_index(operation.args[0], operation.args[1], operation.options)
      when :remove_index
        remove_index(operation.args[0], operation.args[1], operation.options)
      when :rename_index
        rename_index(*operation.args.first(3))
      when :add_foreign_key
        add_foreign_key(operation.args[0], operation.args[1], operation.options)
      when :remove_foreign_key
        remove_foreign_key(operation.args[0], operation.args[1], operation.options)
      when :add_reference
        apply_add_reference(operation)
      when :remove_reference
        apply_remove_reference(operation)
      when :add_timestamps
        add_column(operation.args[0], :created_at, :datetime, operation.options)
        add_column(operation.args[0], :updated_at, :datetime, operation.options)
      when :remove_timestamps
        remove_column(operation.args[0], :created_at)
        remove_column(operation.args[0], :updated_at)
      end
    rescue UnknownSchemaStateError
      # State tracking is best-effort for compilation; explicit predicates remain strict.
    end

    def apply_all(operations)
      operations.each { |op| apply(op) }
      self
    end

    private

    def require_known_table!(name)
      table = @tables[name.to_s]
      unless table&.known
        raise UnknownSchemaStateError,
              "Schema state for table #{name} is unknown. Enable schema snapshot loading or avoid state-dependent migration logic."
      end
      table
    end

    def apply_add_reference(operation)
      table, ref = operation.args.first(2)
      options = operation.options
      type = options[:type] || :bigint
      if options[:polymorphic]
        add_column(table, "#{ref}_type", :string, options.reject { |k, _| %i[index foreign_key polymorphic type].include?(k) })
      end
      add_column(table, "#{ref}_id", type, options.reject { |k, _| %i[index foreign_key polymorphic type].include?(k) })
      add_index(table, options[:polymorphic] ? ["#{ref}_type", "#{ref}_id"] : "#{ref}_id", normalize_index_options(options[:index])) unless options[:index] == false
      if options[:foreign_key]
        to_table = options[:foreign_key].is_a?(Hash) && options[:foreign_key][:to_table] || Util.pluralize(ref)
        add_foreign_key(table, to_table, column: "#{ref}_id")
      end
    end

    def apply_remove_reference(operation)
      table, ref = operation.args.first(2)
      options = operation.options
      remove_column(table, "#{ref}_type") if options[:polymorphic]
      remove_column(table, "#{ref}_id")
    end

    def normalize_index_options(value)
      case value
      when Hash then value
      when String, Symbol then { name: value.to_s }
      else {}
      end
    end
  end
end
