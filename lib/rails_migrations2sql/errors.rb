# frozen_string_literal: true

module RailsMigrations2sql
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class MigrationNotFoundError < Error; end
  class OfflineCompilationError < Error; end
  class UnsupportedOperationError < OfflineCompilationError; end
  class IrreversibleOperationError < OfflineCompilationError; end
  class UnknownSchemaStateError < OfflineCompilationError; end
end
