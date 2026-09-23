# frozen_string_literal: true

module RailsMigrations2sql
  module OfflineGuard
    # Scoped to Active Record's current execution context. Does not disconnect
    # application pools or prevent arbitrary Ruby from bypassing Active Record.
    def self.protect
      previous_handler = ActiveRecord::Base.connection_handler
      ActiveRecord::Base.connection_handler = ConnectionHandler.new
      yield
    ensure
      ActiveRecord::Base.connection_handler = previous_handler
    end

    class ConnectionHandler < ActiveRecord::ConnectionAdapters::ConnectionHandler
      def retrieve_connection_pool(*)
        reject_connection!
      end

      def establish_connection(*)
        reject_connection!
      end

      private

      def reject_connection!
        raise UnsupportedOperationError,
              "Active Record database access cannot be compiled offline; " \
              "use migration DSL or execute with SQL reviewed by the DBA"
      end
    end
  end
end
