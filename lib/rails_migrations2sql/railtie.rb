# frozen_string_literal: true

module RailsMigrations2sql
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("../tasks/rails_migrations2sql.rake", __dir__)
    end
  end
end
