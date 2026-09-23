# rails_migrations2sql

`rails_migrations2sql` compiles Rails 8 migration files into DBA-ready SQL **without executing the migration**.

It is designed for teams where developers create Rails migrations normally, but production DDL must be reviewed and executed by a DBA.

## What it does

Given:

```ruby
class AddStatusToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :status, :string, null: false, default: "pending"
    add_index :orders, :status
  end
end
```

Run:

```bash
bin/rails dba:sql VERSION=20260923130000 TARGET=postgresql
```

The gem writes:

```text
db/dba_migrations/postgresql/20260923130000_add_status_to_orders/
├── up.sql
├── down.sql
├── register.sql
├── unregister.sql
└── manifest.yml
```

No `db:migrate` is run. No shadow database is required.

## Supported targets

- PostgreSQL
- MySQL
- MariaDB
- Oracle
- Microsoft SQL Server

The target is a compiler dialect, not a live connection.

## Installation

```ruby
group :development do
  gem "rails_migrations2sql"
end
```

Then:

```bash
bundle install
bin/rails generate rails_migrations2sql:install
```

Configure the target in `config/initializers/rails_migrations2sql.rb`:

```ruby
RailsMigrations2sql.configure do |config|
  config.target = :oracle
  config.strict = true
end
```

## Commands

Latest migration:

```bash
bin/rails dba:sql TARGET=postgresql
```

Specific migration:

```bash
bin/rails dba:sql VERSION=20260923130000 TARGET=oracle
```

Several migrations:

```bash
bin/rails dba:sql VERSIONS=20260923130000,20260923131500 TARGET=sqlserver
```

Range:

```bash
bin/rails dba:sql FROM=20260923000000 TO=20260923999999 TARGET=mysql
```

All migration files:

```bash
bin/rails dba:sql:all TARGET=mariadb
```

Generate every dialect:

```bash
bin/rails dba:sql VERSION=20260923130000 TARGET=all
```

## Offline architecture

The migration class is loaded as Ruby, but the schema-changing DSL is replaced by an in-memory sandbox.

```text
migration.rb
    |
    v
MigrationSandbox
    |
    v
Operations / IR
    |
    +--> PostgreSQL compiler
    +--> MySQL compiler
    +--> MariaDB compiler
    +--> Oracle compiler
    +--> SQL Server compiler
    |
    v
*.sql
```

`create_table`, `add_column`, `add_index`, references, foreign keys and related commands are recorded as operations instead of being sent to Active Record's database connection.

## Supported migration DSL

The initial offline compiler supports the common structural migration operations:

- `create_table` / `drop_table`
- `create_join_table` / `drop_join_table`
- `add_column` / `remove_column` / `remove_columns`
- `rename_column` / `rename_table`
- `change_column`
- `change_column_default`
- `change_column_null`
- `add_index` / `remove_index` / `rename_index`
- `add_reference` / `remove_reference` (`belongs_to` aliases too)
- `add_foreign_key` / `remove_foreign_key`
- `add_check_constraint` / `remove_check_constraint`
- `add_timestamps` / `remove_timestamps`
- `change_table`
- `reversible`
- `up_only`
- block-form `revert`
- `execute` for literal SQL
- PostgreSQL `enable_extension` / `disable_extension`

`create_table` supports common `TableDefinition` calls such as `string`, `text`, `integer`, `bigint`, `decimal`, `boolean`, `date`, `datetime`, `timestamp`, `binary`, `json`, `jsonb`, `uuid`, `references`, `timestamps`, `index` and `foreign_key`.

## Rollbacks

For a `change` migration the gem reverses operations offline.

```ruby
add_column :orders, :status, :string
add_index :orders, :status
```

becomes a `down.sql` containing the inverse operations in reverse order.

When Rails-style reversal is ambiguous, the gem refuses to guess. For example:

```ruby
remove_column :orders, :legacy_code
```

has no type information, so an offline compiler cannot know how to recreate it. Supply the type:

```ruby
remove_column :orders, :legacy_code, :string
```

Likewise, for an offline-reversible `change_column`, include the old definition:

```ruby
change_column :orders, :total, :decimal,
  precision: 15,
  scale: 2,
  from: { type: :decimal, precision: 10, scale: 2 }
```

If a rollback cannot be generated, `up.sql` is still generated and `down.sql` explains why rollback is unavailable.

## `execute`

Literal SQL is supported for `up` migrations:

```ruby
def up
  execute <<~SQL
    CREATE VIEW active_users AS
    SELECT * FROM users WHERE active = true
  SQL
end
```

For a `change` migration, raw `execute` is not automatically reversible. Use `reversible`:

```ruby
def change
  reversible do |dir|
    dir.up { execute "CREATE VIEW ..." }
    dir.down { execute "DROP VIEW ..." }
  end
end
```

Raw SQL is emitted as written. Portability is therefore the migration author's responsibility.

## Database-dependent Ruby is intentionally rejected

This gem does not query production, development, or a shadow database to decide what a migration means.

Migrations that depend on application data are outside the safe offline subset, for example:

```ruby
Order.where(status: nil).update_all(status: "pending")

if Order.count > 1_000_000
  add_index :orders, :created_at
end
```

Those operations require real data and should be handled as explicit data-maintenance scripts or literal DBA-reviewed SQL.

## Optional `schema.rb` snapshot

Some structural migrations use predicates such as:

```ruby
if column_exists?(:users, :legacy_code)
  remove_column :users, :legacy_code, :string
end
```

The compiler can optionally load `db/schema.rb` into an in-memory virtual schema. It does **not** execute that schema against a database.

```ruby
RailsMigrations2sql.configure do |config|
  config.use_schema_snapshot = true
  config.schema_path = Rails.root.join("db", "schema.rb")
end
```

Leave this disabled when `schema.rb` does not represent the state immediately before the migration being compiled.

## `schema_migrations`

The gem intentionally separates DDL from Rails bookkeeping.

The DBA flow is normally:

1. Review `up.sql`.
2. Execute `up.sql` in production.
3. Validate the schema change.
4. Execute `register.sql` to insert the migration version into `schema_migrations`.

For rollback, review `unregister.sql` and `down.sql` with the DBA before execution.

## Important limitations

This is an offline compiler, not a live Active Record adapter. Some database behavior depends on server version or existing metadata. Strict mode prefers an error over guessed SQL.

Examples include changing nullability in MySQL/MariaDB or SQL Server when the existing column type is unknown, adapter-specific extensions, database-specific index features, and arbitrary Ruby/data migrations.

For critical production changes, review generated SQL against the exact database/version used in production.

## Development status

Version `0.0.1` is the first offline-compiler design. The core compiler is intentionally conservative and should be integration-tested against the database versions used by your organization before production adoption.
