# frozen_string_literal: true

module RailsMigrations2sql
  class Generator
    Result = Struct.new(:packages, :migrations, :targets, keyword_init: true)

    def initialize(configuration = RailsMigrations2sql.configuration)
      @configuration = configuration
      @configuration.validate!
      @discovery = MigrationDiscovery.new(@configuration)
      @loader = MigrationLoader.new
    end

    def generate(version: nil, versions: nil, from: nil, to: nil, all: false, latest: false, target: nil)
      migrations = @discovery.select(version: version, versions: versions, from: from, to: to, all: all, latest: latest)
      targets = resolve_targets(target)
      packages = []

      targets.each do |target_name|
        compiler = CompilerFactory.build(target_name, @configuration)
        schema = base_schema

        migrations.each do |migration_file|
          klass = @loader.load_class(migration_file)
          evaluation = MigrationEvaluator.new(
            migration_file: migration_file,
            migration_class: klass,
            compiler: compiler,
            base_schema: schema
          ).evaluate

          up_sql = compiler.compile(evaluation.up_operations)
          down_sql = evaluation.rollback_available ? compiler.compile(evaluation.down_operations) : []
          writer = PackageWriter.new(
            migration_file: migration_file,
            compiler: compiler,
            configuration: @configuration,
            evaluation: evaluation,
            up_sql: up_sql,
            down_sql: down_sql
          )
          packages << writer.write
          schema = evaluation.schema_after
        end
      end

      Result.new(packages: packages, migrations: migrations, targets: targets)
    end

    private

    def resolve_targets(target)
      requested = target || @configuration.target
      values = Array(requested).flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:empty?)
      return Configuration::SUPPORTED_TARGETS if values.map(&:downcase).include?("all")

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
      root = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root.to_s : Dir.pwd
      File.join(root, "db", "schema.rb")
    end
  end
end
