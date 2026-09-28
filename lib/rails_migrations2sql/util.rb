# frozen_string_literal: true

require "digest"
require "active_support/core_ext/object/deep_dup"

module RailsMigrations2sql
  module Util
    module_function

    def underscore(value)
      value.to_s
           .gsub(/::/, "/")
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
           .gsub(/([a-z\d])([A-Z])/, '\\1_\\2')
           .tr("-", "_")
           .downcase
    end

    def camelize(value)
      if defined?(ActiveSupport::Inflector)
        ActiveSupport::Inflector.camelize(value.to_s)
      else
        value.to_s.split("_").map(&:capitalize).join
      end
    end

    def pluralize(value)
      if defined?(ActiveSupport::Inflector)
        ActiveSupport::Inflector.pluralize(value.to_s)
      else
        value.to_s.end_with?("s") ? value.to_s : "#{value}s"
      end
    end

    def singularize(value)
      if defined?(ActiveSupport::Inflector)
        ActiveSupport::Inflector.singularize(value.to_s)
      else
        value.to_s.sub(/s\z/, "")
      end
    end

    def join_table_name(first, second)
      ActiveRecord::ModelSchema.derive_join_table_name(first.to_s, second.to_s)
    end

    def default_index_name(table, columns)
      "index_#{table}_on_#{Array(columns).map(&:to_s).join('_and_')}"
    end

    def default_foreign_key_name(table, column)
      digest = Digest::SHA256.hexdigest("#{table}_#{Array(column).join('_and_')}_fk")[0, 10]
      "fk_rails_#{digest}"
    end

    def change_value(changes, key)
      changes.key?(key) ? changes[key] : changes[key.to_s]
    end

    def table_columns(columns, options, primary_key_type: :bigint)
      columns = Array(columns).deep_dup
      return columns if options[:id] == false || options[:primary_key].is_a?(Array) ||
                        columns.any? { |column| column.dig(:options, :primary_key) }

      id_options = options[:id].is_a?(Hash) ? options[:id].dup : {}
      type = id_options.delete(:type) || (options[:id] unless options[:id].is_a?(Hash))
      type = primary_key_type if type.nil? || type == true
      type = type.to_sym
      columns.unshift(
        name: (options[:primary_key] || "id").to_s, type: type,
        options: { primary_key: true, null: false,
                   auto_increment: %i[primary_key integer bigint].include?(type) }.merge(id_options)
      )
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = value }
    end
  end
end
