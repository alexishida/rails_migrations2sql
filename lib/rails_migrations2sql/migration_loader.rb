# frozen_string_literal: true

module RailsMigrations2sql
  class MigrationLoader
    def load_class(migration_file)
      load migration_file.path
      klass = constantize(migration_file.class_name)
      return klass if migration_class?(klass)

      candidate = migration_candidates(migration_file.path).last
      return candidate if candidate

      raise OfflineCompilationError,
            "Could not find an ActiveRecord::Migration class in #{migration_file.path}. Expected #{migration_file.class_name}."
    rescue SyntaxError, LoadError => e
      raise OfflineCompilationError, "Could not load #{migration_file.path}: #{e.message}"
    end

    private

    def constantize(name)
      if defined?(ActiveSupport::Inflector)
        ActiveSupport::Inflector.safe_constantize(name)
      else
        Object.const_get(name)
      end
    rescue NameError
      nil
    end

    def migration_class?(klass)
      klass.is_a?(Class) && defined?(ActiveRecord::Migration) && klass < ActiveRecord::Migration
    end

    def migration_candidates(path)
      expanded = File.expand_path(path)
      ObjectSpace.each_object(Class).select do |klass|
        next false unless migration_class?(klass)

        %i[change up down].any? do |method_name|
          next false unless klass.instance_methods(false).include?(method_name)
          location = klass.instance_method(method_name).source_location&.first
          location && File.expand_path(location) == expanded
        end
      rescue StandardError
        false
      end
    end
  end
end
