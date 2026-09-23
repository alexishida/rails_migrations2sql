# frozen_string_literal: true

require_relative "test_helper"
require "generators/rails_migrations2sql/uninstall_generator"
require "tmpdir"
require "fileutils"

class UninstallGeneratorTest < Minitest::Test
  INITIALIZER = "config/initializers/rails_migrations2sql.rb"

  def test_removes_dependency_and_initializer_but_preserves_sql_and_other_initializers
    with_application do |directory|
      generator = build_generator(directory)
      capture_subprocess_io { generator.invoke_all }

      refute_includes File.read(File.join(directory, "Gemfile")), 'gem "rails_migrations2sql"'
      refute_includes File.read(File.join(directory, "Gemfile.lock")), "rails_migrations2sql"
      refute File.exist?(File.join(directory, INITIALIZER))
      assert_equal "SELECT 1;\n", File.read(File.join(directory, "db/sql/postgresql/existing.sql"))
      assert_equal "# Keep\n", File.read(File.join(directory, "config/initializers/other.rb"))
    end
  end

  def test_pretend_does_not_change_files_or_run_bundler
    with_application do |directory|
      original = file_contents(directory)
      generator = build_generator(directory, pretend: true)
      generator.define_singleton_method(:run_bundle_remove) { raise "Must not run Bundler in pretend mode" }

      capture_io { generator.invoke_all }
      assert_equal original, file_contents(directory)
    end
  end

  def test_bundler_failure_restores_dependency_files_and_preserves_initializer
    with_application do |directory|
      original = file_contents(directory)
      generator = build_generator(directory)
      generator.define_singleton_method(:run_bundle_remove) do
        File.write(File.join(destination_root, "Gemfile"), "# Partial modification\n")
        File.write(File.join(destination_root, "Gemfile.lock"), "partial lock\n")
        false
      end

      error = assert_raises(Rails::Generators::Error) { generator.invoke_all }
      assert_includes error.message, "dependency files were restored"
      assert_equal original, file_contents(directory)
    end
  end

  def test_failed_removal_does_not_leave_a_new_lockfile
    with_application do |directory|
      File.delete(File.join(directory, "Gemfile.lock"))
      original = file_contents(directory)
      generator = build_generator(directory)
      generator.define_singleton_method(:run_bundle_remove) do
        File.write(File.join(destination_root, "Gemfile.lock"), "partial lock\n")
        raise "Bundler process failed"
      end

      assert_raises(RuntimeError) { generator.invoke_all }
      assert_equal original, file_contents(directory)
    end
  end

  def test_missing_initializer_does_not_prevent_removal
    with_application do |directory|
      File.delete(File.join(directory, INITIALIZER))
      generator = build_generator(directory)
      capture_subprocess_io { generator.invoke_all }
      refute_includes File.read(File.join(directory, "Gemfile")), 'gem "rails_migrations2sql"'
    end
  end

  private

  def build_generator(directory, **options)
    RailsMigrations2sql::Generators::UninstallGenerator.new([], options, destination_root: directory)
  end

  def file_contents(directory)
    Dir[File.join(directory, "**", "*")].select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }
  end

  def with_application
    Dir.mktmpdir("rails-migrations2sql-uninstall") do |directory|
      FileUtils.mkdir_p(File.join(directory, "config/initializers"))
      FileUtils.mkdir_p(File.join(directory, "db/sql/postgresql"))
      File.write(File.join(directory, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"

        group :development do
          gem "rails_migrations2sql",
              git: "https://github.com/alexishida/rails_migrations2sql.git",
              branch: "main"
        end
      RUBY
      File.write(File.join(directory, "Gemfile.lock"), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:

        PLATFORMS
          ruby

        DEPENDENCIES

        BUNDLED WITH
           #{Bundler::VERSION}
      LOCK
      File.write(File.join(directory, INITIALIZER), "RailsMigrations2sql.configure { |config| config.target = :postgresql }\n")
      File.write(File.join(directory, "config/initializers/other.rb"), "# Keep\n")
      File.write(File.join(directory, "db/sql/postgresql/existing.sql"), "SELECT 1;\n")
      yield directory
    end
  end
end
