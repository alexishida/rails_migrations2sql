# frozen_string_literal: true

require "fileutils"
require "tempfile"

module RailsMigrations2sql
  # Rendering finishes before any output is replaced. Each replacement is atomic;
  # a filesystem failure can still interrupt a batch between different files.
  class OutputFile
    def initialize(path:, content:)
      @path = path.to_s
      @content = content
    end

    def write
      directory = File.dirname(@path)
      FileUtils.mkdir_p(directory)
      mode = File.exist?(@path) ? File.stat(@path).mode & 0o777 : 0o666 & ~File.umask
      Tempfile.create([".rails_migrations2sql-", ".sql"], directory) do |file|
        file.write(@content)
        file.flush
        file.chmod(mode)
        file.close
        File.rename(file.path, @path)
      end
      @path
    end
  end
end
