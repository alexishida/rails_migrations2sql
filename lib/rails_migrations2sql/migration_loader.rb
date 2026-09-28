# frozen_string_literal: true

module RailsMigrations2sql
  class MigrationLoader
    def load_class(migration_file)
      namespace = Module.new
      load migration_file.path, namespace
      klass = namespace.const_get(migration_file.class_name, false) if namespace.const_defined?(migration_file.class_name, false)
      return klass if migration_class?(klass)

      candidates = namespace.constants(false).filter_map do |name|
        candidate = namespace.const_get(name, false)
        candidate if migration_class?(candidate)
      end
      return candidates.first if candidates.length == 1

      raise OfflineCompilationError,
            "Could not find an unambiguous ActiveRecord::Migration class in #{migration_file.path}. Expected #{migration_file.class_name}."
    rescue StandardError, SyntaxError, LoadError => e
      error_class = e.is_a?(UnsupportedOperationError) ? UnsupportedOperationError : OfflineCompilationError
      raise error_class, "Could not load #{migration_file.path}: #{e.class}: #{e.message}"
    end

    private

    def migration_class?(klass)
      klass.is_a?(Class) && klass < ActiveRecord::Migration
    end
  end
end
