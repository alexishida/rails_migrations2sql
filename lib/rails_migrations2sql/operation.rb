# frozen_string_literal: true

module RailsMigrations2sql
  Operation = Struct.new(:name, :args, :options, :data, :source, keyword_init: true) do
    def initialize(name:, args: [], options: {}, data: nil, source: nil)
      super(name: name.to_sym, args: Array(args), options: options || {}, data: data, source: source)
    end

    def to_h
      {
        "name" => name.to_s,
        "args" => args,
        "options" => options,
        "data" => data,
        "source" => source
      }
    end
  end

  OperationGroup = Struct.new(:operations, :label, keyword_init: true) do
    def initialize(operations:, label: nil)
      super(operations: Array(operations), label: label)
    end

    def to_h
      { "group" => label, "operations" => operations.map(&:to_h) }
    end
  end
end
