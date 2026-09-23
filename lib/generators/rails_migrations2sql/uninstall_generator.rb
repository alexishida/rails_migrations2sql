# frozen_string_literal: true

require "rails/generators"
require "bundler"

module RailsMigrations2sql
  module Generators
    class UninstallGenerator < Rails::Generators::Base
      desc "Remove rails_migrations2sql from the application, preserving generated SQL."

      def uninstall
        raise Rails::Generators::Error, "Use rails generate rails_migrations2sql:uninstall" if behavior == :revoke
        raise Rails::Generators::Error, "Gemfile not found in #{destination_root}" unless File.file?(File.join(destination_root, "Gemfile"))

        if options[:pretend]
          say "Would run bundle remove rails_migrations2sql and remove config/initializers/rails_migrations2sql.rb"
          return
        end

        remove_dependency
        remove_file "config/initializers/rails_migrations2sql.rb"
        say "rails_migrations2sql removed. Generated SQL files were preserved.", :green
      end

      private

      def remove_dependency
        snapshots = %w[Gemfile Gemfile.lock].to_h do |filename|
          path = File.join(destination_root, filename)
          [path, File.file?(path) ? File.binread(path) : nil]
        end

        raise Rails::Generators::Error, "bundle remove failed; dependency files were restored" unless run_bundle_remove
      rescue StandardError
        snapshots&.each do |path, contents|
          contents.nil? ? FileUtils.rm_f(path) : File.binwrite(path, contents)
        end
        raise
      end

      def run_bundle_remove
        bundle = Gem.bin_path("bundler", "bundle", Bundler::VERSION)
        Bundler.with_unbundled_env do
          system(
            { "BUNDLE_GEMFILE" => File.join(destination_root, "Gemfile") },
            Gem.ruby, bundle, "remove", "rails_migrations2sql",
            chdir: destination_root
          )
        end
      end
    end
  end
end
