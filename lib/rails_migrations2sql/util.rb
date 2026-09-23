# frozen_string_literal: true

require "digest"

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

    def default_index_name(table, columns)
      "index_#{table}_on_#{Array(columns).map(&:to_s).join('_and_')}"
    end

    def default_foreign_key_name(table, column)
      digest = Digest::SHA256.hexdigest("#{table}_#{column}_fk")[0, 10]
      "fk_rails_#{digest}"
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = value }
    end
  end
end
