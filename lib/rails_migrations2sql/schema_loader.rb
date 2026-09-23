# frozen_string_literal: true

module RailsMigrations2sql
  class SchemaLoader
    def initialize(path)
      @path = path
    end

    def load
      schema = VirtualSchema.new
      return schema unless @path && File.file?(@path)

      body = extract_body(File.read(@path))
      SchemaSandbox.new(schema).instance_eval(body, @path, 1)
      schema
    rescue StandardError => e
      raise OfflineCompilationError, "Could not load schema snapshot #{@path}: #{e.class}: #{e.message}"
    end

    private

    def extract_body(content)
      lines = content.lines
      start = lines.index { |line| line.include?("ActiveRecord::Schema") && line.include?(".define") }
      raise OfflineCompilationError, "Could not locate ActiveRecord::Schema.define in #{@path}" unless start

      tail = lines[(start + 1)..]
      finish = tail.rindex { |line| line.match?(/^end\s*$/) }
      raise OfflineCompilationError, "Could not locate final schema block end in #{@path}" unless finish

      tail[0...finish].join
    end

    class SchemaSandbox
      def initialize(schema)
        @schema = schema
      end

      def create_table(name, **_options)
        definition = TableDefinition.new(name)
        yield definition if block_given?
        @schema.create_table(name, **definition.to_h)
      end

      def add_index(table, columns, **options)
        @schema.add_index(table, columns, options)
      end

      def add_foreign_key(from_table, to_table, **options)
        @schema.add_foreign_key(from_table, to_table, options)
      end

      def enable_extension(*); end
      def disable_extension(*); end
      def create_schema(*); end
      def create_enum(*); end
      def add_check_constraint(*); end
      def add_exclusion_constraint(*); end
      def add_unique_constraint(*); end

      def method_missing(name, *_args, **_kwargs, &_block)
        # schema.rb can contain adapter-specific dump helpers. They are irrelevant
        # unless a later migration asks a state-dependent question about them.
        return nil if name.to_s.start_with?("add_", "create_", "enable_")

        super
      end
    end
  end
end
