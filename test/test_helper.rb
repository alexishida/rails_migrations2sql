# frozen_string_literal: true

require "minitest/autorun"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

require "rails_migrations2sql/errors"
require "rails_migrations2sql/util"
require "rails_migrations2sql/operation"
require "rails_migrations2sql/virtual_schema"
require "rails_migrations2sql/table_definition"
require "rails_migrations2sql/inverter"
require "rails_migrations2sql/recorder"
require "rails_migrations2sql/offline_connection"
require "rails_migrations2sql/migration_sandbox"
require "rails_migrations2sql/compilers/base"
require "rails_migrations2sql/compilers/postgresql"
require "rails_migrations2sql/compilers/mysql"
require "rails_migrations2sql/compilers/oracle"
require "rails_migrations2sql/compilers/sqlserver"
require "rails_migrations2sql/migration_file"
require "rails_migrations2sql/migration_evaluator"
