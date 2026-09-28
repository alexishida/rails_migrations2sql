# frozen_string_literal: true

require "json"
require "time"

module RailsMigrations2sql
  # Declarative local data sources. This compiler never evaluates application seeds.
  class SeedDataset < SeedScript
    def prepare
      @statements.clear
      OfflineGuard.protect do
        @configuration.seed_sources.each_with_index do |source, index|
          @source_description = "seed source #{index + 1} (#{source[:model]})"
          compile_source(source)
        end
      end
      output_file("configured seed sources")
    rescue StandardError, SyntaxError, LoadError => e
      raise OfflineCompilationError, "Offline seed compilation failed at #{@source_description}: #{e.class}: #{e.message}"
    end

    private

    def compile_source(source)
      model = resolve_model(source.fetch(:model))
      records = source_records(source)
      records.each_with_index do |record, position|
        attributes = source_attributes(source, record)
        attributes[source[:position]] = position if source[:position]
        defaults = evaluate(source.fetch(:defaults, {}))
        attributes = defaults.merge(attributes)
        source.fetch(:references, {}).each do |column, lookup|
          related = resolve_model(lookup.fetch(:model))
          value = record.fetch(lookup.fetch(:source).to_s)
          attributes[column] = reference(related, lookup.fetch(:column), value, primary_key: lookup.fetch(:primary_key, :id))
        end
        values = attributes.to_h do |name, value|
          type = source.fetch(:types, {})[name.to_sym]
          [ column_name(model, name), seed_value(value, type) ]
        end
        insert_record(model.table_name, values, primary_key: source.fetch(:primary_key, :id), sequence: source[:sequence], timestamps: source.fetch(:timestamps, true))
        compile_rich_texts(model, source, record, values)
      end
    end

    def source_records(source)
      if source.key?(:path)
        root = @configuration.seed_sources_root || (defined?(Rails) && Rails.respond_to?(:root) && Rails.root) || Dir.pwd
        file = File.expand_path(source.fetch(:path).to_s, root.to_s)
        @source_description += " from #{file}"
        data = JSON.parse(File.read(file))
        data = data.fetch(source[:key].to_s) if source[:key]
      else
        data = evaluate(source.fetch(:records))
      end
      records = data.is_a?(Hash) ? [ data ] : data
      unless records.is_a?(Array) && records.all? { |record| record.is_a?(Hash) || record.is_a?(Array) }
        raise ConfigurationError, "Seed source records must be a Hash or an Array of records"
      end
      records.map { |record| record.is_a?(Hash) ? record.transform_keys(&:to_s) : record }
    end

    def source_attributes(source, record)
      columns = source[:columns]
      return record.dup if columns.nil? && record.is_a?(Hash)
      if columns.is_a?(Array)
        if record.is_a?(Array)
          raise ConfigurationError, "Seed row does not match its declared columns" unless columns.length == record.length
          return columns.zip(record).to_h
        end
        return columns.to_h { |name| [ name, record.fetch(name.to_s) ] }
      end
      unless columns.is_a?(Hash) && record.is_a?(Hash)
        raise ConfigurationError, "Seed columns must map the source record"
      end
      columns.to_h do |name, mapping|
        if mapping.is_a?(Hash)
          value = record.fetch(mapping.fetch(:source).to_s)
          value = evaluate(mapping[:map]).fetch(value) if mapping[:map]
        else
          value = record.fetch(mapping.to_s)
        end
        [ name, value ]
      end
    end

    def compile_rich_texts(model, source, record, attributes)
      source.fetch(:rich_texts, {}).each do |name, options|
        lookup = options.fetch(:lookup)
        column = column_name(model, lookup)
        record_id = reference(model, lookup, attributes.fetch(column), primary_key: source.fetch(:primary_key, :id))
        insert_record("action_text_rich_texts", {
          "name" => name.to_s, "record_type" => model.polymorphic_name,
          "record_id" => record_id, "body" => seed_value(record.fetch(options.fetch(:source).to_s), :text)
        }, primary_key: :id, sequence: options[:sequence])
      end
    end

    def insert_record(table, attributes, primary_key:, sequence:, timestamps: true)
      if target == :oracle && primary_key.to_s == "id" && !attributes.key?("id") && sequence != false
        name = sequence || "#{table}_seq"
        attributes = { "id" => sql("#{quote_table(name)}.NEXTVAL") }.merge(attributes)
      end
      if timestamps
        now = sql("CURRENT_TIMESTAMP")
        attributes = attributes.merge("created_at" => attributes.fetch("created_at", now), "updated_at" => attributes.fetch("updated_at", now))
      end
      insert table, attributes
    end

    def reference(model, column, value, primary_key:)
      condition = value.nil? ? "IS NULL" : "= #{quote(value)}"
      sql("(SELECT #{quote_column(column_name(model, primary_key))} FROM #{quote_table(model.table_name)} " \
          "WHERE #{quote_column(column_name(model, column))} #{condition})")
    end

    def seed_value(value, type)
      return value if value.nil? || value.is_a?(Expression)
      if %i[numeric_boolean oracle_boolean_string].include?(type) && value != true && value != false
        raise ConfigurationError, "Seed boolean values must be true, false or nil"
      end
      case type
      when :numeric_boolean then value ? "1" : "0"
      when :oracle_boolean_string then target == :oracle ? (value ? "Y" : "N") : value
      when :datetime then timestamp(value)
      when :text then clob(value)
      when nil then value
      else raise ConfigurationError, "Unsupported seed type: #{type.inspect}"
      end
    end

    def timestamp(value)
      time = if value.is_a?(String)
        Time.zone ? Time.zone.parse(value) : Time.iso8601(value)
      else
        value
      end
      time = ActiveRecord.default_timezone == :utc ? time.utc : time.getlocal
      literal = quote(time.strftime("%Y-%m-%d %H:%M:%S.%6N"))
      expression = case target
      when :oracle then "TO_TIMESTAMP(#{literal}, 'YYYY-MM-DD HH24:MI:SS.FF6')"
      when :postgresql then "TIMESTAMP #{literal}"
      when :mysql, :mariadb then "CAST(#{literal} AS DATETIME(6))"
      when :sqlserver then "CAST(#{literal} AS datetime2(6))"
      end
      sql(expression)
    end

    def clob(value)
      return value unless target == :oracle && value.is_a?(String) && quote(value).bytesize > 4000
      chunks = []
      chunk = +""
      size = 0
      value.each_char do |character|
        bytes = character == "'" ? 2 : character.bytesize
        if size + bytes > 3998
          chunks << chunk
          chunk = +""
          size = 0
        end
        chunk << character
        size += bytes
      end
      chunks << chunk
      sql(chunks.map { |part| "TO_CLOB(#{quote(part)})" }.join(" || "))
    end

    def resolve_model(model)
      model.is_a?(String) || model.is_a?(Symbol) ? model.to_s.constantize : model
    end

    def column_name(model, name)
      model.attribute_aliases.fetch(name.to_s, name.to_s)
    end

    def evaluate(value)
      value.respond_to?(:call) ? value.call : value
    end
  end
end
