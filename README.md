# rails_migrations2sql

Gem que converte migrations do Rails 8 em pacotes SQL para revisão e execução por DBAs. O compilador registra as operações de estrutura em memória e gera os scripts no dialeto escolhido, sem aplicar essas operações a um banco de dados.

O projeto atende equipes em que desenvolvedores escrevem migrations normalmente, mas as alterações de produção precisam passar pela revisão de um DBA.

[Repositório](https://github.com/alexishida/rails_migrations2sql) · [Issues](https://github.com/alexishida/rails_migrations2sql/issues) · [Licença MIT](LICENSE.txt)

## Requisitos

- Aplicação Rails 8.x: as dependências `activerecord`, `activesupport` e `railties` aceitam versões `>= 8.0` e `< 9.0`.
- Ruby compatível com o Rails escolhido. O gemspec declara `>= 3.2`, mas as dependências podem exigir uma versão superior.
- Bundler e Git para instalar diretamente do GitHub.

A compilação não exige um banco auxiliar. As tarefas carregam o ambiente da aplicação Rails, portanto seus initializers e dependências também precisam estar configurados.

## Instalação pelo GitHub

No `Gemfile` **da aplicação Rails que utilizará a gem**, adicione:

```ruby
group :development do
  gem "rails_migrations2sql",
      git: "https://github.com/alexishida/rails_migrations2sql.git",
      branch: "main"
end
```

Em seguida, na aplicação:

```bash
bundle install
bin/rails generate rails_migrations2sql:install
```

A opção `git:` faz o Bundler baixar esta gem do repositório informado. O comando `bundle` também executa a instalação. O gerador cria `config/initializers/rails_migrations2sql.rb`.

O `Gemfile.lock` registra o commit instalado. Para buscar uma atualização da gem na branch `main`:

```bash
bundle update rails_migrations2sql
```

Versione o `Gemfile.lock` da aplicação para compartilhar a mesma revisão com a equipe. Também é possível fixar um commit com `ref:` no lugar de `branch:`. Consulte a [documentação de fontes Git do Bundler](https://guides.rubygems.org/git/).

Os links do repositório no gemspec são metadados; a origem do download é definida por `git:` no Gemfile da aplicação.

## Uso rápido

Considere o arquivo `db/migrate/20260923130000_add_status_to_orders.rb`:

```ruby
class AddStatusToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :status, :string, null: false, default: "pending"
    add_index :orders, :status
  end
end
```

Gere os pacotes desde essa versão até a última migration disponível, usando o banco configurado:

```bash
bin/rails dba:sql FROM=20260923130000
```

O comando inclui a versão `20260923130000` e todas as posteriores, em ordem crescente, gerando um pacote por migration. Não é necessário informar `TO` nem `TARGET`.

Com a configuração padrão (PostgreSQL), o pacote da migration acima fica em:

```text
db/sql/postgresql/20260923130000_add_status_to_orders/
├── up.sql
├── down.sql
├── register.sql
├── unregister.sql
└── manifest.yml
```

| Arquivo | Conteúdo |
|---|---|
| `up.sql` | SQL para aplicar a alteração. |
| `down.sql` | SQL de reversão ou comentário explicando por que o rollback está indisponível. |
| `register.sql` | Inserção da versão em `schema_migrations`. |
| `unregister.sql` | Remoção da versão de `schema_migrations`. |
| `manifest.yml` | Metadados, SHA-256 do arquivo de origem, operações, avisos e disponibilidade do rollback. |

A geração não chama `db:migrate` nem executa os scripts produzidos. Gerar novamente o mesmo pacote sobrescreve seus arquivos.

## Bancos de destino

| Banco | Valor de `TARGET` |
|---|---|
| PostgreSQL | `postgresql` |
| MySQL | `mysql` |
| MariaDB | `mariadb` |
| Oracle | `oracle` |
| Microsoft SQL Server | `sqlserver` |

O destino seleciona o dialeto do compilador; não representa uma conexão ativa com o banco. Use `TARGET=all` para gerar pacotes para todos os dialetos.

## Configuração

Edite `config/initializers/rails_migrations2sql.rb`:

```ruby
RailsMigrations2sql.configure do |config|
  config.target = :oracle
  config.strict = true
  config.output_path = Rails.root.join("db", "sql")
  config.use_schema_snapshot = false
  config.primary_key_type = :bigint
  config.schema_migrations_table_name = "schema_migrations"
end
```

| Opção | Padrão | Finalidade |
|---|---|---|
| `target` | `RAILS_DBA_TARGET` ou `postgresql` | Dialeto padrão; pode ser sobrescrito por `TARGET`. |
| `output_path` | `db/sql` na raiz da aplicação | Diretório dos pacotes gerados. |
| `migrations_paths` | Caminhos do Active Record ou `db/migrate` | Diretórios de migrations. |
| `strict` | `true` | Interrompe a compilação para operações não suportadas. |
| `use_schema_snapshot` | `false` | Carrega um schema virtual a partir de `schema.rb`. |
| `schema_path` | `db/schema.rb` na raiz da aplicação | Arquivo do snapshot opcional. |
| `primary_key_type` | `bigint` | Tipo padrão de chave primária. |
| `schema_migrations_table_name` | `schema_migrations` | Tabela usada nos scripts de controle de versão. |

O initializer gerado define `config.target = :postgresql` explicitamente. Para usar o padrão de `RAILS_DBA_TARGET`, remova essa atribuição.

## Comandos

Execute na raiz da aplicação Rails:

```bash
# Comando mais simples: migration mais recente, no banco configurado
bin/rails dba:sql

# Da versão informada até a última migration, incluindo a versão inicial
bin/rails dba:sql FROM=20260923130000

# Todos os arquivos de migration
bin/rails dba:sql:all

# Seleção explícita da mais recente
bin/rails dba:sql:latest

# Uma versão
bin/rails dba:sql VERSION=20260923130000

# Várias versões
bin/rails dba:sql VERSIONS=20260923130000,20260923131500

# Intervalo inclusivo de versões
bin/rails dba:sql FROM=20260923000000 TO=20260923999999

# Alternativa para selecionar todos os arquivos
bin/rails dba:sql ALL=1

# Escolher outro banco apenas para esta execução
bin/rails dba:sql TARGET=oracle

# Uma versão em todos os dialetos
bin/rails dba:sql VERSION=20260923130000 TARGET=all
```

### Da versão inicial até a última migration

Para gerar um lote a partir de uma versão conhecida, informe apenas `FROM`:

```bash
bin/rails dba:sql FROM=20260923130000
```

Esse comando inclui `20260923130000` e todas as migrations posteriores disponíveis nos arquivos do projeto, em ordem crescente de versão. Não é necessário informar `TO` nem conhecer a última versão: o limite final é a maior versão disponível. Cada migration gera seu próprio pacote SQL.

Use `FROM` para esse lote; `VERSION=20260923130000` seleciona somente aquela migration. A seleção não consulta o banco para verificar quais versões já foram aplicadas.

Para gerar o mesmo lote em outro dialeto:

```bash
bin/rails dba:sql FROM=20260923130000 TARGET=oracle
```

### Banco de destino e parâmetros opcionais

`TARGET` não é obrigatório: quando omitido, a gem usa `config.target` do initializer. Sem uma atribuição no initializer, usa `RAILS_DBA_TARGET` e, na ausência dessa variável, `postgresql`. O banco não é detectado automaticamente a partir de `config/database.yml`.

`VERSION`, `VERSIONS`, `FROM`, `TO`, `ALL` e `TARGET` são parâmetros opcionais. Sem seleção, a tarefa usa o arquivo de maior versão. A seleção considera os arquivos disponíveis, sem consultar quais migrations já foram aplicadas no banco.

## Operações suportadas

O compilador cobre as operações estruturais comuns da DSL:

- Tabelas: `create_table`, `drop_table`, `rename_table`, `create_join_table`, `drop_join_table` e `change_table`.
- Colunas: `add_column`, `remove_column`, `remove_columns`, `rename_column`, `change_column`, `change_column_default` e `change_column_null`.
- Índices: `add_index`, `remove_index` e `rename_index`.
- Referências: `add_reference` e `remove_reference`, incluindo aliases de `belongs_to`.
- Restrições: `add_foreign_key`, `remove_foreign_key`, `add_check_constraint` e `remove_check_constraint`.
- Timestamps: `add_timestamps` e `remove_timestamps`.
- Controle de direção: `reversible`, `up_only` e `revert` com bloco.
- SQL literal: `execute`.
- Extensões do PostgreSQL: `enable_extension` e `disable_extension`.

Em `create_table`, estão disponíveis chamadas como `string`, `text`, `integer`, `bigint`, `decimal`, `boolean`, `date`, `datetime`, `timestamp`, `binary`, `json`, `jsonb`, `uuid`, `references`, `timestamps`, `index` e `foreign_key`.

As opções disponíveis variam conforme o dialeto. O suporte a uma operação não implica suporte a todas as opções dos adapters do Active Record.

## Rollback e SQL literal

Para migrations com `change`, as operações reversíveis geram um `down.sql` com as operações inversas em ordem reversa. Quando a reversão precisa da definição anterior, informe-a:

```ruby
# O tipo é necessário para recriar a coluna no rollback.
remove_column :orders, :legacy_code, :string

# A definição anterior permite reverter a alteração.
change_column :orders, :total, :decimal,
  precision: 15,
  scale: 2,
  from: { type: :decimal, precision: 10, scale: 2 }
```

Se a avaliação identificar que a migration não é reversível, o pacote ainda inclui `up.sql`; `down.sql` explica o impedimento e o manifesto registra a indisponibilidade.

SQL literal pode ser usado em `up`:

```ruby
def up
  execute <<~SQL
    CREATE VIEW active_users AS
    SELECT * FROM users WHERE active = true
  SQL
end
```

Em `change`, use `reversible` para informar as duas direções:

```ruby
def change
  reversible do |dir|
    dir.up { execute "CREATE VIEW active_users AS SELECT * FROM users WHERE active = true" }
    dir.down { execute "DROP VIEW active_users" }
  end
end
```

O conteúdo de `execute` é emitido como escrito. Sua compatibilidade com o banco de destino é responsabilidade de quem escreve a migration.

## Snapshot opcional de schema

Predicados como `column_exists?` podem precisar de informações sobre a estrutura anterior:

```ruby
if column_exists?(:users, :legacy_code)
  remove_column :users, :legacy_code, :string
end
```

Para fornecer essas informações, habilite o carregamento de `schema.rb` em memória:

```ruby
RailsMigrations2sql.configure do |config|
  config.use_schema_snapshot = true
  config.schema_path = Rails.root.join("db", "schema.rb")
end
```

O snapshot não é aplicado ao banco. Ele deve representar o estado imediatamente anterior à primeira migration selecionada; deixe a opção desabilitada se o arquivo não corresponder a esse estado.

## Fluxo de execução pelo DBA

1. Gere o pacote para o banco de destino.
2. Revise `up.sql` e o manifesto.
3. Execute `up.sql` no ambiente autorizado e valide a alteração.
4. Execute `register.sql` para registrar a versão em `schema_migrations`.

Para rollback, revise `down.sql` e `unregister.sql` com o DBA e execute a remoção do registro após reverter a alteração com sucesso.

Os scripts de registro pressupõem que a tabela de controle já exista. A geração mantém o SQL de alteração separado do controle de versões do Rails.

## Funcionamento e limitações

A classe da migration é carregada como Ruby. O `MigrationSandbox` intercepta as chamadas da DSL suportada, registra operações em memória e as encaminha ao compilador do dialeto escolhido. O `PackageWriter` grava os scripts e o manifesto.

O compilador não consulta dados da aplicação para decidir o que gerar. Migrations que dependem de modelos ou consultas, como as abaixo, ficam fora do fluxo offline suportado:

```ruby
Order.where(status: nil).update_all(status: "pending")

if Order.count > 1_000_000
  add_index :orders, :created_at
end
```

Trate essas alterações como scripts explícitos de manutenção de dados ou SQL revisado pelo DBA. Como o código Ruby da migration é avaliado, o sandbox da DSL não isola chamadas arbitrárias a modelos ou outros efeitos colaterais.

Algumas operações dependem do tipo atual da coluna ou de recursos específicos do servidor. Exemplos incluem alterar nulabilidade no MySQL, MariaDB ou SQL Server, índices específicos de cada banco e extensões de adapters. O modo estrito interrompe operações não suportadas.

A versão `0.0.1` representa a implementação inicial do compilador offline. Revise o SQL e valide-o nas versões de banco utilizadas pela equipe antes da adoção em produção.

## Desenvolvimento e testes

Para trabalhar no código da gem:

```bash
git clone https://github.com/alexishida/rails_migrations2sql.git
cd rails_migrations2sql
bundle install
bundle exec rake test
```

Neste repositório, o `Gemfile` usa `gemspec` para carregar a gem local e instalar suas dependências de desenvolvimento. A declaração com `git:` da seção de instalação pertence às aplicações consumidoras.

A suíte usa Minitest; a tarefa padrão `bundle exec rake` também executa os testes.

| Caminho | Responsabilidade |
|---|---|
| [lib/rails_migrations2sql/](lib/rails_migrations2sql/) | Descoberta e avaliação de migrations, schema virtual e geração dos pacotes. |
| [lib/rails_migrations2sql/compilers/](lib/rails_migrations2sql/compilers/) | Compiladores dos dialetos SQL. |
| [lib/tasks/rails_migrations2sql.rake](lib/tasks/rails_migrations2sql.rake) | Tarefas `dba:sql`. |
| [lib/generators/rails_migrations2sql/](lib/generators/rails_migrations2sql/) | Gerador do initializer de configuração. |
| [test/](test/) | Testes do compilador offline. |

## Contribuição e licença

Relate problemas nas [issues](https://github.com/alexishida/rails_migrations2sql/issues), incluindo a migration, o dialeto e o resultado esperado. Para contribuir, envie um pull request com a alteração e os testes pertinentes.

Distribuído sob a [licença MIT](LICENSE.txt).
