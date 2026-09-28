# frozen_string_literal: true

module RailsMigrations2sql
  class Generator
    Result = Struct.new(:packages, :migrations, :targets, keyword_init: true)

    def initialize(configuration = RailsMigrations2sql.configuration)
      @configuration = configuration
      @discovery = MigrationDiscovery.new(@configuration)
      @loader = MigrationLoader.new
    end

    def generate(version: nil, versions: nil, from: nil, to: nil, all: false, latest: false, target: nil, seeds: :auto)
      OfflineGuard.protect do
        generate_packages(version: version, versions: versions, from: from, to: to, all: all, latest: latest, target: target, seeds: seeds)
      end
    end

    def generate_seeds(target: nil)
      OfflineGuard.protect do
        targets = resolve_targets(target)
        files = prepare_seeds(targets, required: true)
        Result.new(packages: files.map(&:write), migrations: [], targets: targets)
      end
    end

    private

    def generate_packages(version:, versions:, from:, to:, all:, latest:, target:, seeds:)
      migrations = @discovery.select(version: version, versions: versions, from: from, to: to, all: all, latest: latest)
      targets = resolve_targets(target)
      unless [true, false, :auto].include?(seeds)
        raise ConfigurationError, "seeds must be true, false or :auto"
      end
      seed_files = seeds == false ? [] : prepare_seeds(targets, required: seeds == true)
      files = []
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
          files << writer.prepare
          schema = evaluation.schema_after
        end
      end

      files.concat(seed_files)
      Result.new(packages: files.map(&:write), migrations: migrations, targets: targets)
    end

    def prepare_seeds(targets, required:)
      path = @configuration.seeds_path || File.join(project_root, "db", "seeds.rb")
      sql_path = @configuration.sql_seeds_path || File.join(File.dirname(path), "seeds_sql.rb")
      if @configuration.sql_seeds_path && !File.file?(sql_path)
        raise ConfigurationError, "SQL seed file not found: #{sql_path}"
      end
      sql_script = File.file?(sql_path)
      unless sql_script || File.file?(path)
        raise ConfigurationError, "Seed file not found: #{path}" if required
        return []
      end
      rows = SeedRecorder.capture(path) unless sql_script
      targets.map do |target_name|
        compiler = CompilerFactory.build(target_name, @configuration)
        if sql_script
          SeedScript.new(compiler: compiler, configuration: @configuration).prepare(sql_path)
        else
          SeedRecorder.prepare(rows, compiler: compiler, configuration: @configuration)
        end
      end
    end

    def resolve_targets(target)
      requested = target || @configuration.target
      values = Array(requested).flat_map { |value| value.to_s.split(",") }.map { |value| value.strip.downcase }.reject(&:empty?).uniq
      raise ConfigurationError, "At least one target must be selected" if values.empty?
      targets = values.map(&:to_sym)
      invalid = targets - Configuration::SUPPORTED_TARGETS - [:all]
      raise ConfigurationError, "Unsupported target(s): #{invalid.join(', ')}" if invalid.any?
      targets.include?(:all) ? Configuration::SUPPORTED_TARGETS : targets
    end

    def base_schema
      return VirtualSchema.new(primary_key_type: @configuration.primary_key_type) unless @configuration.use_schema_snapshot

      path = @configuration.schema_path || default_schema_path
      SchemaLoader.new(path, primary_key_type: @configuration.primary_key_type).load
    end

    def default_schema_path
      File.join(project_root, "db", "schema.rb")
    end

    def project_root
      defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root.to_s : Dir.pwd
    end
  end
end
