# frozen_string_literal: true

module RailsMigrations2sql
  class Generator
    Result = Struct.new(:packages, :migrations, :targets, keyword_init: true)

    def initialize(configuration = RailsMigrations2sql.configuration)
      @configuration = configuration
      @discovery = MigrationDiscovery.new(@configuration)
      @loader = MigrationLoader.new
    end

    def generate(version: nil, versions: nil, from: nil, to: nil, all: false, latest: false, target: nil)
      OfflineGuard.protect do
        generate_packages(version: version, versions: versions, from: from, to: to, all: all, latest: latest, target: target)
      end
    end

    def generate_seeds(target: nil)
      OfflineGuard.protect do
        targets = resolve_targets(target)
        rows = load_seed_rows(required: true)
        Result.new(packages: write_seeds(rows, targets), migrations: [], targets: targets)
      end
    end

    private

    def generate_packages(version:, versions:, from:, to:, all:, latest:, target:)
      migrations = @discovery.select(version: version, versions: versions, from: from, to: to, all: all, latest: latest)
      targets = resolve_targets(target)
      seed_rows = load_seed_rows(required: false)
      packages = []
      initial_schema = base_schema
      migration_classes = {}

      targets.each do |target_name|
        compiler = CompilerFactory.build(target_name, @configuration)
        schema = initial_schema.dup

        migrations.each do |migration_file|
          klass = migration_classes[migration_file.path] ||= @loader.load_class(migration_file)
          evaluation = MigrationEvaluator.new(
            migration_file: migration_file,
            migration_class: klass,
            compiler: compiler,
            base_schema: schema,
            copy_schema: false
          ).evaluate

          up_sql = compiler.compile(evaluation.up_operations)
          writer = PackageWriter.new(
            migration_file: migration_file,
            compiler: compiler,
            configuration: @configuration,
            up_sql: up_sql
          )
          packages << writer.write
          schema = evaluation.schema_after
        end
      end

      packages.concat(write_seeds(seed_rows, targets)) if seed_rows
      Result.new(packages: packages, migrations: migrations, targets: targets)
    end

    def load_seed_rows(required:)
      path = @configuration.seeds_path || File.join(project_root, "db", "seeds.rb")
      unless File.file?(path)
        raise ConfigurationError, "Seed file not found: #{path}" if required
        return nil
      end

      SeedRecorder.capture(path)
    end

    def write_seeds(rows, targets)
      targets.map do |target_name|
        compiler = CompilerFactory.build(target_name, @configuration)
        SeedRecorder.write(rows, compiler: compiler, configuration: @configuration)
      end
    end

    def resolve_targets(target)
      requested = target || @configuration.target
      values = Array(requested).flat_map { |value| value.to_s.split(",") }.map { |value| value.strip.downcase }.reject(&:empty?).uniq
      raise ConfigurationError, "At least one target must be selected" if values.empty?
      return Configuration::SUPPORTED_TARGETS if values.include?("all")

      targets = values.map(&:to_sym)
      invalid = targets - Configuration::SUPPORTED_TARGETS
      raise ConfigurationError, "Unsupported target(s): #{invalid.join(', ')}" if invalid.any?
      targets
    end

    def base_schema
      return VirtualSchema.new unless @configuration.use_schema_snapshot

      path = @configuration.schema_path || default_schema_path
      SchemaLoader.new(path).load
    end

    def default_schema_path
      File.join(project_root, "db", "schema.rb")
    end

    def project_root
      defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root.to_s : Dir.pwd
    end
  end
end
