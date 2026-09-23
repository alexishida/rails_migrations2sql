# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/rails_migrations2sql"
Dir.mktmpdir("sql-generation-benchmark") do |root|
  migrations = File.join(root, "migrate")
  Dir.mkdir(migrations)
  count = Integer(ENV.fetch("MIGRATIONS", "120"))
  count.times do |index|
    File.write(File.join(migrations, "#{20260101000000 + index}_benchmark_migration#{index}.rb"), <<~SOURCE)
      class BenchmarkMigration#{index} < ActiveRecord::Migration[8.0]
        def change
          create_table :benchmark_table_#{index} do |t|
            #{20.times.map { |column| "t.string :column_#{column}, default: 'value'" }.join("\n")}
          end
        end
      end
    SOURCE
  end
  config = RailsMigrations2sql::Configuration.new
  config.migrations_paths = [migrations]
  config.output_path = File.join(root, "sql")
  GC.start
  allocated = GC.stat(:total_allocated_objects)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = RailsMigrations2sql::Generator.new(config).generate(all: true, target: :all)
  duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  puts "files=#{result.packages.length} seconds=#{duration.round(3)} allocations=#{GC.stat(:total_allocated_objects) - allocated}"
end
