# frozen_string_literal: true

module RailsMigrations2sql
  module Inverter
    module_function

    def invert(operation)
      name = operation.name
      args = operation.args
      opts = operation.options

      case name
      when :create_table
        Operation.new(name: :drop_table, args: [args[0]], options: opts, source: operation.source)
      when :drop_table
        data = operation.data
        raise IrreversibleOperationError, "drop_table #{args[0]} is reversible offline only when a table definition block is provided" unless data
        Operation.new(name: :create_table, args: [args[0]], options: opts, data: data, source: operation.source)
      when :rename_table
        Operation.new(name: :rename_table, args: [args[1], args[0]], source: operation.source)
      when :add_column
        Operation.new(name: :remove_column, args: [args[0], args[1], args[2]], options: opts, source: operation.source)
      when :remove_column
        type = args[2] || opts[:type]
        raise IrreversibleOperationError, "remove_column #{args[0]}.#{args[1]} requires the column type to generate down SQL" unless type
        Operation.new(name: :add_column, args: [args[0], args[1], type], options: opts.reject { |k, _| k == :type }, source: operation.source)
      when :remove_columns
        types = opts[:types]
        common_type = opts[:type]
        unless types.is_a?(Hash) || common_type
          raise IrreversibleOperationError, "remove_columns requires type: or types: { column: :type } for offline reversal"
        end
        operations = args.drop(1).map do |column|
          type = common_type || types[column.to_sym] || types[column.to_s]
          raise IrreversibleOperationError, "Missing type for removed column #{column}" unless type
          Operation.new(name: :add_column, args: [args[0], column, type], source: operation.source)
        end
        OperationGroup.new(operations: operations, label: "invert_remove_columns")
      when :rename_column
        Operation.new(name: :rename_column, args: [args[0], args[2], args[1]], source: operation.source)
      when :change_column
        from = opts[:from]
        raise IrreversibleOperationError, "change_column #{args[0]}.#{args[1]} requires from: { type:, ... } for offline reversal" unless from.is_a?(Hash) && from[:type]
        Operation.new(name: :change_column, args: [args[0], args[1], from[:type]], options: from.reject { |k, _| k == :type }, source: operation.source)
      when :change_column_default
        changes = args[2]
        unless changes.is_a?(Hash) && (changes.key?(:from) || changes.key?("from")) && (changes.key?(:to) || changes.key?("to"))
          raise IrreversibleOperationError, "change_column_default requires from:/to: to generate down SQL"
        end
        from = changes[:from] || changes["from"]
        to = changes[:to] || changes["to"]
        Operation.new(name: :change_column_default, args: [args[0], args[1], { from: to, to: from }], source: operation.source)
      when :change_column_null
        Operation.new(name: :change_column_null, args: [args[0], args[1], !args[2], args[3]], options: opts, source: operation.source)
      when :add_index
        remove_opts = {}
        remove_opts[:name] = opts[:name] if opts[:name]
        Operation.new(name: :remove_index, args: [args[0], args[1]], options: remove_opts, source: operation.source)
      when :remove_index
        columns = args[1] || opts[:column]
        raise IrreversibleOperationError, "remove_index on #{args[0]} requires column(s) to generate down SQL" unless columns
        Operation.new(name: :add_index, args: [args[0], columns], options: opts.reject { |k, _| k == :column }, source: operation.source)
      when :rename_index
        Operation.new(name: :rename_index, args: [args[0], args[2], args[1]], source: operation.source)
      when :add_reference
        Operation.new(name: :remove_reference, args: args.first(2), options: opts, source: operation.source)
      when :remove_reference
        Operation.new(name: :add_reference, args: args.first(2), options: opts, source: operation.source)
      when :add_foreign_key
        remove_opts = {}
        remove_opts[:name] = opts[:name] if opts[:name]
        remove_opts[:column] = opts[:column] if opts[:column]
        Operation.new(name: :remove_foreign_key, args: args.first(2), options: remove_opts, source: operation.source)
      when :remove_foreign_key
        to_table = args[1]
        raise IrreversibleOperationError, "remove_foreign_key requires the referenced table to generate down SQL" unless to_table
        Operation.new(name: :add_foreign_key, args: args.first(2), options: opts, source: operation.source)
      when :add_check_constraint
        remove_opts = {}
        remove_opts[:name] = opts[:name] if opts[:name]
        Operation.new(name: :remove_check_constraint, args: [args[0], args[1]], options: remove_opts, source: operation.source)
      when :remove_check_constraint
        expression = args[1] || opts[:expression]
        raise IrreversibleOperationError, "remove_check_constraint requires the expression to generate down SQL" unless expression
        Operation.new(name: :add_check_constraint, args: [args[0], expression], options: opts, source: operation.source)
      when :add_timestamps
        Operation.new(name: :remove_timestamps, args: [args[0]], options: opts, source: operation.source)
      when :remove_timestamps
        Operation.new(name: :add_timestamps, args: [args[0]], options: opts, source: operation.source)
      when :create_join_table
        Operation.new(name: :drop_join_table, args: args, options: opts, source: operation.source)
      when :drop_join_table
        raise IrreversibleOperationError, "drop_join_table requires a definition block for offline reversal" unless operation.data
        Operation.new(name: :create_join_table, args: args, options: opts, data: operation.data, source: operation.source)
      when :enable_extension
        Operation.new(name: :disable_extension, args: args, options: opts, source: operation.source)
      when :disable_extension
        Operation.new(name: :enable_extension, args: args, options: opts, source: operation.source)
      when :change_table_comment, :change_column_comment
        changes = args.last
        unless changes.is_a?(Hash) && (changes.key?(:from) || changes.key?("from")) && (changes.key?(:to) || changes.key?("to"))
          raise IrreversibleOperationError, "#{name} requires from:/to: to generate down SQL"
        end
        swapped = { from: changes[:to] || changes["to"], to: changes[:from] || changes["from"] }
        Operation.new(name: name, args: args[0...-1] + [swapped], options: opts, source: operation.source)
      when :execute
        raise IrreversibleOperationError, "execute is not automatically reversible; use reversible { |dir| ... } or explicit up/down methods"
      else
        raise IrreversibleOperationError, "#{name} is not reversible by the offline compiler"
      end
    end

    def invert_sequence(operations)
      operations.reverse.map do |operation|
        inverted = invert(operation)
        inverted.is_a?(OperationGroup) ? inverted.operations : [inverted]
      end.flatten
    end
  end
end
