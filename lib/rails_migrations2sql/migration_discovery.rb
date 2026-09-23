# frozen_string_literal: true

module RailsMigrations2sql
  class MigrationDiscovery
    FILE_PATTERN = /\A(\d+)_([a-z0-9_]+)\.rb\z/

    def initialize(configuration = RailsMigrations2sql.configuration)
      @configuration = configuration
    end

    def all
      paths.flat_map do |dir|
        Dir[File.join(dir, "*.rb")].filter_map do |path|
          match = FILE_PATTERN.match(File.basename(path))
          next unless match

          MigrationFile.new(
            path: File.expand_path(path),
            version: match[1],
            name: match[2],
            class_name: Util.camelize(match[2])
          )
        end
      end.sort_by { |migration| migration.version.to_i }
    end

    def select(version: nil, versions: nil, from: nil, to: nil, all: false, latest: false)
      migrations = self.all
      requested = Array(versions || version).compact.flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:empty?)

      selected = if requested.any?
                   migrations.select { |migration| requested.include?(migration.version.to_s) }
                 elsif from || to
                   migrations.select do |migration|
                     number = migration.version.to_i
                     (!from || number >= from.to_i) && (!to || number <= to.to_i)
                   end
                 elsif all
                   migrations
                 elsif latest || !migrations.empty?
                   migrations.last ? [migrations.last] : []
                 else
                   []
                 end

      if requested.any?
        missing = requested - selected.map { |migration| migration.version.to_s }
        raise MigrationNotFoundError, "Migration version(s) not found: #{missing.join(', ')}" if missing.any?
      end

      raise MigrationNotFoundError, "No migration files found in #{paths.join(', ')}" if selected.empty?
      selected
    end

    def paths
      configured = @configuration.migrations_paths
      return Array(configured).map { |path| File.expand_path(path.to_s) } if configured

      if defined?(ActiveRecord::Migrator) && ActiveRecord::Migrator.respond_to?(:migrations_paths)
        Array(ActiveRecord::Migrator.migrations_paths).map { |path| File.expand_path(path.to_s, rails_root) }
      else
        [File.join(rails_root, "db", "migrate")]
      end
    end

    private

    def rails_root
      defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root.to_s : Dir.pwd
    end
  end
end
