# frozen_string_literal: true

module RailsMigrations2sql
  MigrationFile = Struct.new(:path, :version, :name, :class_name, keyword_init: true) do
    def filename
      File.basename(path)
    end

    def stem
      File.basename(path, ".rb")
    end

    def to_h
      { "path" => path, "version" => version.to_s, "name" => name, "class_name" => class_name }
    end
  end
end
