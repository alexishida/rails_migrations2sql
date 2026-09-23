# frozen_string_literal: true

module RailsMigrations2sql
  class MigrationEvaluator
    Result = Struct.new(:up_operations, :down_operations, :rollback_available, :rollback_error, :schema_after, keyword_init: true)

    def initialize(migration_file:, migration_class:, compiler:, base_schema: VirtualSchema.new)
      @migration_file = migration_file
      @migration_class = migration_class
      @compiler = compiler
      @base_schema = base_schema
    end

    def evaluate
      change_mode = defines_instance_method?(:change)
      up_method = change_mode ? :change : :up
      unless change_mode || defines_instance_method?(:up) || @migration_class.respond_to?(:up)
        raise OfflineCompilationError, "#{@migration_file.filename} defines neither change nor up"
      end

      up_schema = @base_schema.dup
      up_recorder = Recorder.new(direction: :up, change_mode: change_mode, schema: up_schema)
      run(up_method, up_recorder)
      up_operations = up_recorder.operations
      schema_after = up_schema

      begin
        down_schema = schema_after.dup
        down_recorder = Recorder.new(direction: :down, change_mode: change_mode, schema: down_schema)
        down_method = change_mode ? :change : :down
        if !change_mode && !defines_instance_method?(:down) && !@migration_class.respond_to?(:down)
          raise IrreversibleOperationError, "Migration has no down method"
        end
        run(down_method, down_recorder)
        down_operations = down_recorder.operations
        rollback_available = true
        rollback_error = nil
      rescue IrreversibleOperationError, UnsupportedOperationError => e
        down_operations = []
        rollback_available = false
        rollback_error = e.message
      end

      Result.new(
        up_operations: up_operations,
        down_operations: down_operations,
        rollback_available: rollback_available,
        rollback_error: rollback_error,
        schema_after: schema_after
      )
    end

    private

    def run(method_name, recorder)
      migration = @migration_class.new(@migration_file.class_name, @migration_file.version.to_i)
      migration.extend(MigrationSandbox)
      migration._rdm_recorder = recorder
      migration._rdm_compiler = @compiler

      if migration.respond_to?(method_name, true)
        migration.__send__(method_name)
      elsif @migration_class.respond_to?(method_name)
        @migration_class.__send__(method_name)
      else
        raise OfflineCompilationError, "#{@migration_file.filename} does not define #{method_name}"
      end
    rescue UnknownSchemaStateError, UnsupportedOperationError, IrreversibleOperationError
      raise
    rescue StandardError => e
      location = e.backtrace&.find { |line| line.include?(@migration_file.filename) }
      suffix = location ? " at #{location}" : ""
      raise OfflineCompilationError,
            "Offline evaluation failed for #{@migration_file.filename} (#{method_name}): #{e.class}: #{e.message}#{suffix}"
    end

    def defines_instance_method?(name)
      @migration_class.instance_methods(false).include?(name) || @migration_class.private_instance_methods(false).include?(name)
    end
  end
end
