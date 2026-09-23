# frozen_string_literal: true

module RailsMigrations2sql
  class Recorder
    attr_reader :direction, :change_mode, :schema

    def initialize(direction:, change_mode:, schema: VirtualSchema.new)
      @direction = direction.to_sym
      @change_mode = change_mode
      @schema = schema
      @units = []
      @explicit_depth = 0
    end

    def record(operation, explicit: false)
      unit = if auto_invert? && !explicit && @explicit_depth.zero?
               Inverter.invert(operation)
             else
               operation
             end
      @units << unit
      apply_to_schema(operation) unless auto_invert? && !explicit && @explicit_depth.zero?
      unit
    end

    def record_group(operations, label:, explicit: true)
      group = OperationGroup.new(operations: operations, label: label)
      @units << group
      operations.each { |operation| apply_to_schema(operation) } unless auto_invert? && !explicit
      group
    end

    def capture_explicit_group(label)
      child = Recorder.new(direction: direction, change_mode: false, schema: schema)
      child.instance_variable_set(:@explicit_depth, @explicit_depth + 1)
      yield child
      record_group(child.operations, label: label, explicit: true)
    end

    def capture_neutral
      child_schema = schema.dup
      child = Recorder.new(direction: :up, change_mode: false, schema: child_schema)
      yield child
      child.operations
    end

    def operations
      units = auto_invert? ? @units.reverse : @units
      flatten(units)
    end

    private

    def auto_invert?
      change_mode && direction == :down
    end

    def flatten(units)
      units.flat_map do |unit|
        unit.is_a?(OperationGroup) ? unit.operations : unit
      end
    end

    def apply_to_schema(operation)
      schema.apply(operation) if operation.is_a?(Operation)
    end
  end
end
