# frozen_string_literal: true

module RailsMigrations2sql
  module MigrationSandbox
    SCHEMA_COMMANDS = %i[
      add_column remove_column rename_column change_column change_column_null
      add_index remove_index rename_index rename_table add_foreign_key remove_foreign_key
      add_check_constraint remove_check_constraint add_timestamps remove_timestamps
      enable_extension disable_extension
    ].freeze

    attr_accessor :_rdm_recorder, :_rdm_compiler

    def connection
      @_rdm_connection ||= OfflineConnection.new(recorder: _rdm_recorder, compiler: _rdm_compiler)
    end

    def create_table(table_name, **options)
      definition = TableDefinition.new(table_name)
      yield definition if block_given?
      op = Operation.new(name: :create_table, args: [table_name.to_s], options: options, data: definition.to_h)
      _rdm_recorder.record(op)
    end

    def drop_table(*table_names, **options)
      table_names.each do |table_name|
        definition = nil
        if block_given?
          table_def = TableDefinition.new(table_name)
          yield table_def
          definition = table_def.to_h
        end
        _rdm_recorder.record(Operation.new(name: :drop_table, args: [table_name.to_s], options: options, data: definition))
      end
    end

    def change_table(table_name, **_options)
      definition = TableDefinition.new(table_name, change_table: true)
      yield definition
      definition.operations.each { |op| _rdm_recorder.record(enrich_from_schema(op)) }
    end

    def create_join_table(table_1, table_2, **options)
      table_name = options[:table_name] || [table_1.to_s, table_2.to_s].sort.join("_")
      definition = TableDefinition.new(table_name)
      definition.column("#{Util.singularize(table_1)}_id", options[:column_options]&.dig(:type) || :bigint, **(options[:column_options] || {}).reject { |k, _| k == :type })
      definition.column("#{Util.singularize(table_2)}_id", options[:column_options]&.dig(:type) || :bigint, **(options[:column_options] || {}).reject { |k, _| k == :type })
      yield definition if block_given?
      _rdm_recorder.record(Operation.new(name: :create_join_table, args: [table_1.to_s, table_2.to_s], options: options, data: definition.to_h))
    end

    def drop_join_table(table_1, table_2, **options)
      definition = nil
      if block_given?
        table_name = options[:table_name] || [table_1.to_s, table_2.to_s].sort.join("_")
        table_def = TableDefinition.new(table_name)
        yield table_def
        definition = table_def.to_h
      end
      _rdm_recorder.record(Operation.new(name: :drop_join_table, args: [table_1.to_s, table_2.to_s], options: options, data: definition))
    end

    def add_reference(table_name, ref_name, **options)
      _rdm_recorder.record(Operation.new(name: :add_reference, args: [table_name.to_s, ref_name.to_s], options: options))
    end
    alias add_belongs_to add_reference

    def remove_reference(table_name, ref_name, **options)
      _rdm_recorder.record(Operation.new(name: :remove_reference, args: [table_name.to_s, ref_name.to_s], options: options))
    end
    alias remove_belongs_to remove_reference

    def remove_columns(table_name, *column_names, **options)
      _rdm_recorder.record(Operation.new(name: :remove_columns, args: [table_name.to_s, *column_names.map(&:to_s)], options: options))
    end

    def change_column_default(table_name, column_name, default_or_changes = nil, **changes)
      value = changes.empty? ? default_or_changes : changes
      _rdm_recorder.record(Operation.new(name: :change_column_default, args: [table_name.to_s, column_name.to_s, value]))
    end

    def change_table_comment(table_name, comment_or_changes = nil, **changes)
      value = changes.empty? ? comment_or_changes : changes
      _rdm_recorder.record(Operation.new(name: :change_table_comment, args: [table_name.to_s, value]))
    end

    def change_column_comment(table_name, column_name, comment_or_changes = nil, **changes)
      value = changes.empty? ? comment_or_changes : changes
      _rdm_recorder.record(Operation.new(name: :change_column_comment, args: [table_name.to_s, column_name.to_s, value]))
    end

    SCHEMA_COMMANDS.each do |command|
      define_method(command) do |*args, **options|
        normalized_args = args.map { |arg| arg.is_a?(Symbol) ? arg.to_s : arg }
        op = Operation.new(name: command, args: normalized_args, options: options)
        _rdm_recorder.record(enrich_from_schema(op))
      end
    end

    def execute(sql, *_args, **_options)
      _rdm_recorder.record(Operation.new(name: :execute, args: [sql.to_s]))
    end

    def reversible
      direction = _rdm_recorder.direction
      selected = []
      helper = Object.new
      helper.define_singleton_method(:up) { |&block| selected << block if direction == :up }
      helper.define_singleton_method(:down) { |&block| selected << block if direction == :down }
      yield helper
      _rdm_recorder.capture_explicit_group("reversible_#{direction}") do |child|
        with_recorder(child) { selected.each(&:call) }
      end
    end

    def up_only(&block)
      return unless _rdm_recorder.direction == :up

      _rdm_recorder.capture_explicit_group("up_only") do |child|
        with_recorder(child, &block)
      end
    end

    def revert(*migration_classes, &block)
      unless migration_classes.empty?
        raise UnsupportedOperationError,
              "revert(SomeMigration) is not supported offline yet; use an explicit revert block or explicit up/down methods"
      end
      raise ArgumentError, "revert requires a block" unless block

      neutral = _rdm_recorder.capture_neutral do |child|
        with_recorder(child, &block)
      end
      operations = if _rdm_recorder.direction == :up
                     Inverter.invert_sequence(neutral)
                   else
                     neutral
                   end
      _rdm_recorder.record_group(operations, label: "revert", explicit: true)
    end

    def table_exists?(table_name)
      _rdm_recorder.schema.table_exists?(table_name)
    end

    def column_exists?(table_name, column_name, type = nil, **options)
      _rdm_recorder.schema.column_exists?(table_name, column_name, type, **options)
    end

    def index_exists?(table_name, columns = nil, **options)
      _rdm_recorder.schema.index_exists?(table_name, columns, **options)
    end

    def foreign_key_exists?(from_table, to_table = nil, **options)
      _rdm_recorder.schema.foreign_key_exists?(from_table, to_table, **options)
    end

    def quote(value)
      _rdm_compiler.literal(value)
    end

    def quote_table_name(value)
      _rdm_compiler.quote_table(value)
    end

    def quote_column_name(value)
      _rdm_compiler.quote_column(value)
    end

    def suppress_messages
      yield
    end

    def safety_assured
      yield
    end

    def say(*); end

    def say_with_time(*)
      yield if block_given?
    end

    private

    def with_recorder(recorder)
      previous = _rdm_recorder
      self._rdm_recorder = recorder
      yield
    ensure
      self._rdm_recorder = previous
    end

    def enrich_from_schema(operation)
      if operation.name == :change_column_null
        column = _rdm_recorder.schema.column(operation.args[0], operation.args[1])
        operation.options[:current_type] ||= column&.type
        operation.options[:current_options] ||= column&.options if column
      elsif operation.name == :remove_column && !operation.args[2]
        column = _rdm_recorder.schema.column(operation.args[0], operation.args[1])
        if column
          operation.args[2] = column.type
          operation.options.merge!(column.options)
        end
      end
      operation
    end
  end
end
