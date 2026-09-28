# rails_migrations2sql

A gem that compiles Rails 8 migrations and seed data into SQL files for DBA review and execution. It records application operations in memory without applying them to a database or evaluating rollbacks.

It is designed for teams where developers write ordinary Rails migrations while production changes must be reviewed and executed by a DBA.

[Repository](https://github.com/alexishida/rails_migrations2sql) · [Issues](https://github.com/alexishida/rails_migrations2sql/issues) · [MIT License](LICENSE.txt)

## Requirements

- Rails 8.x. The `activerecord`, `activesupport`, and `railties` dependencies support versions `>= 8.0` and `< 9.0`.
- A Ruby version compatible with the selected Rails version. The gemspec requires Ruby `>= 3.2`.
- Bundler and Git for installation from GitHub.

Compilation does not require an auxiliary database. Rails still loads the application environment, so its initializers and dependencies must be configured.

## Installation from GitHub

Add this to the **Rails application's** `Gemfile`:

```ruby
group :development do
  gem "rails_migrations2sql",
      git: "https://github.com/alexishida/rails_migrations2sql.git",
      branch: "main"
end
```

Then run:

```bash
bundle install
bin/rails generate rails_migrations2sql:install
```

The generator creates `config/initializers/rails_migrations2sql.rb`. `Gemfile.lock` records the installed commit; update it with:

```bash
bundle update rails_migrations2sql
```

Commit `Gemfile.lock` so the whole team uses the same revision. You can pin a specific commit with `ref:` instead of `branch:`; see the [Bundler Git source documentation](https://guides.rubygems.org/git/).

## Uninstallation

From the Rails application root:

```bash
bin/rails generate rails_migrations2sql:uninstall
```

The generator removes the dependency with `bundle remove rails_migrations2sql`, updates `Gemfile.lock`, and removes its initializer only after Bundler succeeds. Generated SQL files and application migrations are preserved, and no database changes are made.

Preview the operation without modifying files:

```bash
bin/rails generate rails_migrations2sql:uninstall --pretend
```

## Quick start

For this migration:

```ruby
class AddStatusToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :status, :string, null: false, default: "pending"
    add_index :orders, :status
  end
end
```

Generate SQL from that version through the latest migration:

```bash
bin/rails dba:sql FROM=20260923130000
```

The initial version and all following migrations are selected in ascending order. In a PostgreSQL project, this migration generates:

```text
db/sql/postgresql/20260923130000_add_status_to_orders.sql
```

Each migration file contains its application SQL followed by a `schema_migrations` version insert. When seeds exist, the command also generates or updates `db/sql/<dialect>/seed.sql`. `config.seed_sources`, when configured, takes precedence over seed scripts. Otherwise `db/seeds_sql.rb` takes precedence over `db/seeds.rb`.

The generator does not call `db:migrate` or execute generated SQL. All selected migrations, dialects, and seeds are compiled before files are written. Compilation errors preserve existing files, and each output file is replaced atomically.

## Target databases

| Database | `TARGET` value |
|---|---|
| PostgreSQL | `postgresql` |
| MySQL | `mysql` |
| MariaDB | `mariadb` |
| Oracle | `oracle` |
| Microsoft SQL Server | `sqlserver` |

By default, the gem detects the dialect from the Rails database configuration without opening a connection. `TARGET` selects the SQL compiler, not a database connection. Use `TARGET=all` to generate every supported dialect.

## Configuration

Configure `config/initializers/rails_migrations2sql.rb`:

```ruby
RailsMigrations2sql.configure do |config|
  config.target = :auto
  config.strict = true
  config.output_path = Rails.root.join("db", "sql")
  config.seeds_path = Rails.root.join("db", "seeds.rb")
  config.use_schema_snapshot = false
  config.primary_key_type = :bigint
  config.schema_migrations_table_name = "schema_migrations"
end
```

| Option | Default | Purpose |
|---|---|---|
| `target` | `auto` | Detects the current environment's primary database adapter, or accepts an explicit dialect. |
| `output_path` | `db/sql` | Directory for generated files. |
| `migrations_paths` | Active Record paths or `db/migrate` | Migration directories. |
| `seeds_path` | `db/seeds.rb` | Rails seed file compiled when present. |
| `seed_sources` | `[]` | Declarative sources compiled by the gem instead of evaluating seed scripts. |
| `seed_sources_root` | Rails root or current directory | Base directory for relative JSON source paths. |
| `sql_seeds_path` | `seeds_sql.rb` next to `seeds_path` | Explicit SQL seed export; takes precedence. |
| `strict` | `true` | Rejects unsupported operations. |
| `use_schema_snapshot` | `false` | Loads a virtual schema from `schema.rb`. |
| `schema_path` | `db/schema.rb` | Optional schema snapshot path. |
| `primary_key_type` | `bigint` | Default primary key type. |
| `schema_migrations_table_name` | `schema_migrations` | Version-tracking table. |

Auto detection uses Rails-resolved configuration, including `database.yml` and `DATABASE_URL`, without querying the server. In a multi-database project it uses `primary`, or the first database-task-enabled configuration when no `primary` configuration exists.

| Rails adapter | Detected dialect |
|---|---|
| `postgresql` | `postgresql` |
| `mysql2`, `trilogy`, `mysql` | `mysql` |
| `mariadb` | `mariadb` |
| `oracle_enhanced`, `oracle` | `oracle` |
| `sqlserver` | `sqlserver` |

MariaDB commonly uses `mysql2`, so it cannot always be distinguished from MySQL. Set `config.target = :mariadb` or `TARGET=mariadb` when needed. Unsupported adapters, including `sqlite3`, require an explicit target.

## Commands

Run commands from the Rails application root:

```bash
# Latest migration for the configured database
bin/rails dba:sql

# From a version through the latest available migration
bin/rails dba:sql FROM=20260923130000

# All migration files
bin/rails dba:sql:all

# Explicit latest-migration selection
bin/rails dba:sql:latest

# Migrations only; do not update seed.sql
bin/rails dba:sql FROM=20260923130000 SEEDS=0

# Seed only
bin/rails dba:sql:seeds

# One or more explicit versions
bin/rails dba:sql VERSION=20260923130000
bin/rails dba:sql VERSIONS=20260923130000,20260923131500

# Inclusive version range
bin/rails dba:sql FROM=20260923000000 TO=20260923999999

# All files or all target dialects
bin/rails dba:sql ALL=1
bin/rails dba:sql VERSION=20260923130000 TARGET=all

# Override the configured target for one invocation
bin/rails dba:sql TARGET=oracle
```

Without a selection, `dba:sql` compiles the highest-version migration. `FROM` and `TO` must contain digits only, and `FROM` cannot be greater than `TO`. Selection considers migration files only; it never checks which migrations have already been applied.

## Seed data

`dba:sql`, `dba:sql:all`, and `dba:sql:latest` automatically update `db/sql/<dialect>/seed.sql`. Without a seed file, they generate only migrations. Use `SEEDS=0` to disable seed generation or `SEEDS=1` to require a seed file. Run `bin/rails dba:sql:seeds` to generate the seed alone.

Each generation overwrites the single `seed.sql` file for the target. Run it after the migrations that create its required tables and columns.

Offline compilation supports `Model.create`, `Model.create!`, `Model.insert_all`, `Model.insert_all!`, and `Model.find_or_create_by`/`find_or_create_by!` with explicit scalar attributes. Every record becomes an `INSERT`; `find_or_create_by` becomes an `INSERT ... WHERE NOT EXISTS`. Record order is preserved.

The generator does not run validations, callbacks, or automatic Active Record timestamps. Provide IDs, timestamps, and other required values explicitly, or rely on schema defaults.

Database-dependent operations such as `where`, `first`, or using generated IDs cannot be compiled offline. They raise an error. Attribute aliases declared through `alias_attribute` are resolved to their actual column names.

For seeds that need query-dependent logic, write `db/seeds_sql.rb`. It is evaluated once per target dialect and offers `target`, `quote`, `quote_table`, `quote_column`, `sql`, `insert`, `update`, and `execute`:

```ruby
now = sql("CURRENT_TIMESTAMP")
lookup = { email: "admin@example.com" }

insert :users, lookup.merge(name: "Administrator", created_at: now, updated_at: now),
  unless_exists: lookup
update :users, { name: "Administrator", updated_at: now }, where: lookup
```

`sql(...)` represents a database expression. `execute(...)` appends SQL without opening a connection. Use only trusted seed files, and review generated SQL before execution.

## Declarative seed sources

For database-dependent Rails seeds, configure data sources in the initializer. The gem handles SQL generation without evaluating `db/seeds.rb`; application tables, input files, and domain mappings stay in the application's configuration.

```ruby
config.seed_sources = [
  {
    model: "Article", path: "db/data/articles.json",
    columns: %i[title slug published_at featured],
    defaults: { status: 1 },
    types: { published_at: :datetime, featured: :oracle_boolean_string },
    references: { category_id: { model: "Category", column: :slug, source: :category } },
    rich_texts: { body: { source: :body, lookup: :slug } }
  }
]
```

`model` accepts a class or a class name and resolves attribute aliases without inspecting the database. `path` reads a JSON file afresh for every generation; `key` selects a top-level key. Alternatively, `records` accepts a Hash, an Array of records, or a callable returning those values. Callables execute under the offline connection guard.

`columns` can be an Array of attributes (also mapping positional JSON rows) or a Hash mapping attributes to source fields. A mapping such as `category: { source: :category, map: -> { Category::LEGACY_CODES } }` applies an explicit value map. Missing keys, unknown mapped values, invalid row shapes, and unsupported types abort generation before any output file is changed. `defaults` accepts a Hash or callable; `position` adds the zero-based input position.

The sources produce INSERTs in order, with `CURRENT_TIMESTAMP` for missing `created_at` and `updated_at`. Set `timestamps: false` for tables without those columns. They do not reproduce validations, callbacks, deletes, or application service behavior. The application must declare the values it intends to export.

For Oracle, an absent numeric `id` uses the declared `sequence` or `<table>_seq`. Set `sequence: false` for identity columns, and declare `primary_key: :email` or another key for records without a numeric `id`. Existing IDs and timestamps are preserved. Other dialects rely on their normal identity/default behavior.

`types` supports `:datetime` (explicit SQL conversion with Rails timezone rules), `:text` (escaped UTF-8 CLOB chunks for long Oracle text), `:numeric_boolean` (`"1"`/`"0"` string columns), and `:oracle_boolean_string` (`"Y"`/`"N"` for Oracle string-emulated boolean columns, native booleans elsewhere). Untyped values use the dialect's normal literal compiler. Boolean types accept only true, false, or nil.

`references` resolve declared source values through scalar subqueries when the DBA applies the output. Each lookup accepts `model`, `column`, `source`, and optional `primary_key` (default `id`). `rich_texts` creates the associated `action_text_rich_texts` INSERTs with the model's polymorphic name; specify the body `source` and a unique record `lookup` column. Categories and other referenced rows must already exist when the SQL is applied.

Configured sources work with `dba:sql`, `dba:sql:seeds`, and migration selections. `SEEDS=0` skips them without evaluating their files or callables. No connection is opened and no generated SQL is executed.

## Supported operations

The compiler supports these common migration DSL operations:

- Tables: `create_table`, `drop_table`, `rename_table`, `create_join_table`, `drop_join_table`, and `change_table`.
- Columns: `add_column`, `remove_column`, `remove_columns`, `rename_column`, `change_column`, `change_column_default`, and `change_column_null`.
- Indexes: `add_index`, `remove_index`, and `rename_index`.
- References: `add_reference` and `remove_reference`, including `belongs_to` aliases.
- Constraints: `add_foreign_key`, `remove_foreign_key`, `add_check_constraint`, and `remove_check_constraint`.
- Timestamps: `add_timestamps` and `remove_timestamps`.
- Direction control: `reversible`, `up_only`, and block-form `revert`.
- Literal SQL: `execute`.
- PostgreSQL extensions: `enable_extension` and `disable_extension`.

In `create_table`, supported definitions include `string`, `text`, `integer`, `bigint`, `decimal`, `boolean`, `date`, `datetime`, `timestamp`, `binary`, `json`, `jsonb`, `uuid`, `references`, `timestamps`, `index`, and `foreign_key`.

The virtual schema tracks tables, primary keys, references, and columns added within the same batch. This lets operations such as `add_column` followed by `change_column_null` use the current type without a snapshot. Dialect-specific options are supported only where the target compiler translates them; strict mode rejects unsupported options.

## Migrations, literal SQL, and snapshots

Write migrations normally using `change` or `up`. The gem evaluates `change` when present, otherwise `up`, once for each target dialect. The `down` method and `dir.down` blocks are not evaluated; this gem does not generate rollback SQL.

Use `execute` when the migration itself needs literal SQL:

```ruby
def change
  execute <<~SQL
    CREATE VIEW active_users AS
    SELECT * FROM users WHERE active = true
  SQL
end
```

Literal SQL is emitted exactly as written. Its compatibility with the selected target is the migration author's responsibility. Query methods such as `select_value`, `select_all`, and `exec_query` require a real database and raise `UnsupportedOperationError`.

For predicates that require prior schema information, enable an in-memory `schema.rb` snapshot:

```ruby
RailsMigrations2sql.configure do |config|
  config.use_schema_snapshot = true
  config.schema_path = Rails.root.join("db", "schema.rb")
end
```

The snapshot is never applied to a database. It must represent the state immediately before the first selected migration.

## DBA execution flow

1. Generate SQL for the target database.
2. Review each `<version>_<name>.sql` file.
3. Run migration files in ascending version order with a client that stops on errors.
4. Run `seed.sql`, if generated, after the required migrations.
5. Validate the data and `schema_migrations` entries.

Each migration file ends with a version `INSERT`. The version-tracking table must exist, and the version must not already be present. The gem does not add a global transaction or generate rollback scripts.

## Limitations

The generator temporarily replaces Active Record's connection handler in the current execution context. Acquiring or creating a connection through Active Record raises `UnsupportedOperationError`, and the previous handler is restored even after a failure.

This is not complete Ruby isolation. Existing connection objects or pools, external database clients, new threads, code that replaces the handler, and arbitrary side effects are outside this guard. Rails initializes before the guard runs. Compile only trusted migrations and seeds.

Model- or query-dependent migrations are outside the supported offline flow:

```ruby
Order.where(status: nil).update_all(status: "pending")

if Order.count > 1_000_000
  add_index :orders, :created_at
end
```

Treat such work as explicit DBA-reviewed maintenance SQL.

## Development and tests

```bash
git clone https://github.com/alexishida/rails_migrations2sql.git
cd rails_migrations2sql
bundle install
bundle exec rake test
```

This repository's `Gemfile` uses `gemspec` to load the local gem. The test suite uses Minitest, and `bundle exec rake` runs it.

| Path | Responsibility |
|---|---|
| [lib/rails_migrations2sql/](lib/rails_migrations2sql/) | Migration and seed discovery/evaluation, virtual schema, and package generation. |
| [lib/rails_migrations2sql/compilers/](lib/rails_migrations2sql/compilers/) | SQL dialect compilers. |
| [lib/tasks/rails_migrations2sql.rake](lib/tasks/rails_migrations2sql.rake) | `dba:sql` and `dba:sql:seeds` tasks. |
| [lib/generators/rails_migrations2sql/](lib/generators/rails_migrations2sql/) | Configuration initializer generator. |
| [test/](test/) | Offline compiler tests. |

## Contributing and license

Report problems in the [issues](https://github.com/alexishida/rails_migrations2sql/issues), including the migration, target dialect, and expected result. Contributions should include relevant tests.

Distributed under the [MIT License](LICENSE.txt).

## Generation benchmark

Run `bundle exec ruby benchmark/generation.rb` to generate 600 temporary files (120 migrations, 20 columns per table, five dialects), measure time and allocations, and remove the files when it finishes. Use `MIGRATIONS=240` to change the volume. The benchmark covers compilation and file writing without database connections.
