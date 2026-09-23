# frozen_string_literal: true

module RailsMigrations2sql
  class TableDefinition
    COLUMN_TYPES = %i[
      string text integer bigint float decimal numeric boolean date datetime timestamp time
      binary json jsonb uuid virtual inet interval enum
    ].freeze

    attr_reader :columns, :indexes, :foreign_keys

    def initialize(table_name, change_table: false)
      @table_name = table_name.to_s
      @change_table = change_table
      @columns = []
      @indexes = []
      @foreign_keys = []
      @operations = []
    end

    COLUMN_TYPES.each do |type|
      define_method(type) do |*names, **options|
        names.each { |name| column(name, type, **options) }
      end
    end

    def column(name, type, **options)
      entry = { name: name.to_s, type: type.to_sym, options: options }
      if @change_table
        @operations << Operation.new(name: :add_column, args: [@table_name, name.to_s, type.to_sym], options: options)
      else
        @columns << entry
      end
      self
    end

    def primary_key(name, type = :primary_key, **options)
      column(name, type, **options.merge(primary_key: true))
    end

    def timestamps(**options)
      options = { null: false }.merge(options)
      column(:created_at, :datetime, **options)
      column(:updated_at, :datetime, **options)
      self
    end

    def references(*names, **options)
      names.each do |name|
        if @change_table
          @operations << Operation.new(name: :add_reference, args: [@table_name, name.to_s], options: options)
        else
          type = options[:type] || :bigint
          col_options = options.reject { |key, _| %i[type polymorphic index foreign_key].include?(key) }
          if options[:polymorphic]
            @columns << { name: "#{name}_type", type: :string, options: col_options }
          end
          @columns << { name: "#{name}_id", type: type.to_sym, options: col_options }

          unless options[:index] == false
            columns = options[:polymorphic] ? ["#{name}_type", "#{name}_id"] : ["#{name}_id"]
            idx_options = case options[:index]
                          when Hash then options[:index]
                          when String, Symbol then { name: options[:index].to_s }
                          else {}
                          end
            @indexes << { columns: columns, options: idx_options }
          end

          if options[:foreign_key]
            fk_options = options[:foreign_key].is_a?(Hash) ? options[:foreign_key].dup : {}
            to_table = fk_options.delete(:to_table) || Util.pluralize(name)
            fk_options[:column] ||= "#{name}_id"
            @foreign_keys << { to_table: to_table.to_s, options: fk_options }
          end
        end
      end
      self
    end
    alias belongs_to references

    def index(columns, **options)
      if @change_table
        @operations << Operation.new(name: :add_index, args: [@table_name, columns], options: options)
      else
        @indexes << { columns: Array(columns).map(&:to_s), options: options }
      end
      self
    end

    def foreign_key(to_table, **options)
      if @change_table
        @operations << Operation.new(name: :add_foreign_key, args: [@table_name, to_table.to_s], options: options)
      else
        @foreign_keys << { to_table: to_table.to_s, options: options }
      end
      self
    end

    def remove(*names, **options)
      ensure_change_table!(:remove)
      names.each { |name| @operations << Operation.new(name: :remove_column, args: [@table_name, name.to_s], options: options) }
      self
    end

    def remove_index(columns = nil, **options)
      ensure_change_table!(:remove_index)
      @operations << Operation.new(name: :remove_index, args: [@table_name, columns], options: options)
      self
    end

    def remove_references(*names, **options)
      ensure_change_table!(:remove_references)
      names.each { |name| @operations << Operation.new(name: :remove_reference, args: [@table_name, name.to_s], options: options) }
      self
    end
    alias remove_belongs_to remove_references

    def remove_foreign_key(to_table = nil, **options)
      ensure_change_table!(:remove_foreign_key)
      @operations << Operation.new(name: :remove_foreign_key, args: [@table_name, to_table&.to_s], options: options)
      self
    end

    def rename(old_name, new_name)
      ensure_change_table!(:rename)
      @operations << Operation.new(name: :rename_column, args: [@table_name, old_name.to_s, new_name.to_s])
      self
    end

    def change(name, type, **options)
      ensure_change_table!(:change)
      @operations << Operation.new(name: :change_column, args: [@table_name, name.to_s, type.to_sym], options: options)
      self
    end

    def change_default(name, default_or_changes)
      ensure_change_table!(:change_default)
      @operations << Operation.new(name: :change_column_default, args: [@table_name, name.to_s, default_or_changes])
      self
    end

    def change_null(name, null, default = nil)
      ensure_change_table!(:change_null)
      @operations << Operation.new(name: :change_column_null, args: [@table_name, name.to_s, null, default])
      self
    end

    def operations
      @operations.dup
    end

    def to_h
      { columns: columns, indexes: indexes, foreign_keys: foreign_keys }
    end

    private

    def ensure_change_table!(method_name)
      return if @change_table

      raise UnsupportedOperationError, "t.#{method_name} is only supported inside change_table"
    end
  end
end
