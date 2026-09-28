# frozen_string_literal: true

module RailsMigrations2sql
  class SqlFormatter
    def initialize(target)
      @target = target.to_sym
    end

    def join(statements)
      Array(statements).map { |statement| format(statement) }.join("\n\n")
    end

    def format(statement)
      sql = statement.to_s.rstrip
      return sql if sql.empty? || sql.lines.all? { |line| line.strip.empty? || line.lstrip.start_with?("--") }

      if @target == :oracle && plsql?(sql)
        body = sql.end_with?(";") ? sql : "#{sql};"
        "#{body}\n/"
      else
        if sql.lines.last.include?("--")
          "#{sql}\n;"
        else
          sql.end_with?(";") ? sql : "#{sql};"
        end
      end
    end

    private

    def plsql?(sql)
      sql.match?(/\A\s*(?:DECLARE|BEGIN)\b/i) && sql.match?(/\bEND\s*;?\s*\z/i)
    end
  end
end
