# frozen_string_literal: true

namespace :dba do
  desc "Compile Rails migration file(s) to DBA SQL without executing migrations"
  task sql: :environment do
    versions = ENV["VERSIONS"] || ENV["VERSION"]
    target = ENV["TARGET"]
    result = RailsMigrations2sql.generate(
      versions: versions,
      from: ENV["FROM"],
      to: ENV["TO"],
      all: ENV["ALL"] == "1",
      latest: versions.to_s.empty? && ENV["FROM"].to_s.empty? && ENV["TO"].to_s.empty? && ENV["ALL"] != "1",
      target: target
    )

    puts "Compiled #{result.migrations.length} migration(s) for #{result.targets.join(', ')}"
    result.packages.each { |path| puts "  #{path}" }
  rescue RailsMigrations2sql::Error => e
    abort "rails_migrations2sql: #{e.message}"
  end

  namespace :sql do
    desc "Compile only db/seeds.rb into seeds.sql without a database connection"
    task seeds: :environment do
      result = RailsMigrations2sql.generate_seeds(target: ENV["TARGET"])
      puts "Compiled seeds for #{result.targets.join(', ')}"
      result.packages.each { |path| puts "  #{path}" }
    rescue RailsMigrations2sql::Error => e
      abort "rails_migrations2sql: #{e.message}"
    end

    desc "Compile every migration file offline"
    task all: :environment do
      result = RailsMigrations2sql.generate(all: true, target: ENV["TARGET"])
      puts "Compiled #{result.migrations.length} migration(s) for #{result.targets.join(', ')}"
      result.packages.each { |path| puts "  #{path}" }
    rescue RailsMigrations2sql::Error => e
      abort "rails_migrations2sql: #{e.message}"
    end

    desc "Compile only the latest migration file offline"
    task latest: :environment do
      result = RailsMigrations2sql.generate(latest: true, target: ENV["TARGET"])
      puts "Compiled #{result.migrations.length} migration(s) for #{result.targets.join(', ')}"
      result.packages.each { |path| puts "  #{path}" }
    rescue RailsMigrations2sql::Error => e
      abort "rails_migrations2sql: #{e.message}"
    end
  end
end
