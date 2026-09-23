# frozen_string_literal: true

require "rails/generators"

module RailsMigrations2sql
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("install/templates", __dir__)

      def copy_initializer
        template "initializer.rb", "config/initializers/rails_migrations2sql.rb"
      end
    end
  end
end
