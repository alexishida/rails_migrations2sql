# rails_migrations2sql

Gem que converte migrations do Rails 8 em um arquivo SQL por migration e por banco de destino, para revisão e execução por DBAs. O compilador registra as operações de aplicação em memória, sem aplicá-las a um banco de dados nem avaliar o rollback.

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

## Desinstalação

Na raiz da aplicação Rails, execute:

```bash
bin/rails generate rails_migrations2sql:uninstall
```

O comando usa `bundle remove rails_migrations2sql` para remover a dependência e atualizar o `Gemfile.lock`. Após o sucesso, remove `config/initializers/rails_migrations2sql.rb`. Os arquivos SQL já gerados e as migrations da aplicação são preservados; nenhuma alteração é feita no banco de dados.

Se o Bundler falhar, o `Gemfile` e o lockfile são restaurados e o initializer é mantido. Para visualizar a ação sem alterar arquivos:

```bash
bin/rails generate rails_migrations2sql:uninstall --pretend
```

Essa operação remove a dependência desta aplicação, sem desinstalar globalmente a gem usada por outros projetos. Consulte a [documentação de bundle remove](https://guides.rubygems.org/command-reference/bundle-remove/).

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

O comando inclui a versão `20260923130000` e todas as posteriores, em ordem crescente, gerando um arquivo SQL por migration. Não é necessário informar `TO` nem `TARGET`.

Em um projeto configurado com PostgreSQL, a migration acima gera apenas este arquivo:

```text
db/sql/postgresql/20260923130000_add_status_to_orders.sql
```

O arquivo contém o SQL de aplicação, seguido da inserção da versão em `schema_migrations`. Nenhum arquivo auxiliar é gerado.

A geração não chama `db:migrate` nem executa os scripts produzidos. Gerar novamente a mesma migration sobrescreve seus arquivos. Pastas e scripts produzidos pelo formato antigo não são removidos automaticamente e não devem ser executados junto com os novos arquivos.

## Bancos de destino

| Banco | Valor de `TARGET` |
|---|---|
| PostgreSQL | `postgresql` |
| MySQL | `mysql` |
| MariaDB | `mariadb` |
| Oracle | `oracle` |
| Microsoft SQL Server | `sqlserver` |

Por padrão, a gem detecta o dialeto pela configuração de banco do projeto Rails, sem abrir conexão. O destino seleciona o dialeto do compilador; não representa uma conexão ativa com o banco. Use `TARGET=all` para gerar arquivos para todos os dialetos.

## Configuração

Edite `config/initializers/rails_migrations2sql.rb`:

```ruby
RailsMigrations2sql.configure do |config|
  config.target = :auto
  config.strict = true
  config.output_path = Rails.root.join("db", "sql")
  config.use_schema_snapshot = false
  config.primary_key_type = :bigint
  config.schema_migrations_table_name = "schema_migrations"
end
```

| Opção | Padrão | Finalidade |
|---|---|---|
| `target` | `auto` | Detecta o adapter do banco principal do ambiente Rails atual; aceita um dialeto explícito. |
| `output_path` | `db/sql` na raiz da aplicação | Diretório dos pacotes gerados. |
| `migrations_paths` | Caminhos do Active Record ou `db/migrate` | Diretórios de migrations. |
| `strict` | `true` | Interrompe a compilação para operações não suportadas. |
| `use_schema_snapshot` | `false` | Carrega um schema virtual a partir de `schema.rb`. |
| `schema_path` | `db/schema.rb` na raiz da aplicação | Arquivo do snapshot opcional. |
| `primary_key_type` | `bigint` | Tipo padrão de chave primária. |
| `schema_migrations_table_name` | `schema_migrations` | Tabela usada pelo registro de versão ao final de cada SQL. |

O initializer gerado usa `config.target = :auto`. A gem consulta a configuração já resolvida pelo Rails (incluindo `database.yml` e `DATABASE_URL` quando aplicável), sem consultar o servidor. Em projetos com vários bancos, escolhe `primary`; se esse nome não existir, usa a primeira configuração habilitada para tarefas de banco no ambiente atual.

| Adapter Rails | Dialeto detectado |
|---|---|
| `postgresql` | `postgresql` |
| `mysql2`, `trilogy`, `mysql` | `mysql` |
| `mariadb` | `mariadb` |
| `oracle_enhanced`, `oracle` | `oracle` |
| `sqlserver` | `sqlserver` |

MariaDB normalmente usa `mysql2`, que não permite distingui-lo de MySQL apenas pela configuração. Para selecionar o dialeto MariaDB, use `config.target = :mariadb` ou `TARGET=mariadb`.

Sem configuração de banco ou com um adapter não suportado, como `sqlite3`, a gem informa um erro e pede um destino explícito. Ela não assume PostgreSQL. Se você já instalou a gem, troque a atribuição antiga do initializer por `config.target = :auto` para ativar a detecção.

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

Esse comando inclui `20260923130000` e todas as migrations posteriores disponíveis nos arquivos do projeto, em ordem crescente de versão. Não é necessário informar `TO` nem conhecer a última versão: o limite final é a maior versão disponível. Cada migration gera seu próprio arquivo SQL.

Use `FROM` para esse lote; `VERSION=20260923130000` seleciona somente aquela migration. A seleção não consulta o banco para verificar quais versões já foram aplicadas.

Para gerar o mesmo lote em outro dialeto:

```bash
bin/rails dba:sql FROM=20260923130000 TARGET=oracle
```

### Banco de destino e parâmetros opcionais

`TARGET` não é obrigatório. A prioridade é: `TARGET` na execução, um `config.target` explícito no initializer e, no modo `auto`, `RAILS_DBA_TARGET` ou a detecção do banco do ambiente Rails atual. Por exemplo, `RAILS_ENV=production bin/rails dba:sql FROM=20260923130000` usa a configuração de produção.

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

`change_column_null :users, :active, false, false`, por exemplo, gera um `UPDATE` dos valores nulos antes de aplicar `NOT NULL`, preservando o valor booleano informado. Defaults com `from:`/`to:` também preservam `false`.

Nomes automáticos de foreign keys compostas e check constraints seguem o algoritmo do Active Record. Ao remover uma constraint criada por um SQL antigo da gem com um nome diferente, informe o nome existente em `name:`.

As opções disponíveis variam conforme o dialeto. O suporte a uma operação não implica suporte a todas as opções dos adapters do Active Record.

## Aplicação da migration e SQL literal

Escreva a migration normalmente com `change` ou `up`. A gem avalia `change` quando ele está definido; caso contrário, avalia `up`. O corpo selecionado é avaliado uma única vez por migration e dialeto. Não é necessário converter a DSL para `execute`.

Cada arquivo de migration e o snapshot são carregados uma vez por chamada de geração. Cada dialeto mantém seu próprio schema virtual, atualizado entre migrations sem copiar toda a estrutura a cada avaliação. O corpo de `change`/`up` continua sendo avaliado por dialeto, inclusive quando consulta `connection.adapter_name`. Uma nova chamada de geração recarrega os arquivos.

O método `down` e os blocos `dir.down` de `reversible` não são avaliados. A gem não gera scripts de rollback nem exige que `change` seja reversível. `up_only` e blocos `dir.up` são incluídos. Um `revert` explícito dentro de `change` ou `up` continua sendo uma operação de aplicação e precisa ser reversível para ser compilado.

Use `execute` quando a própria migration precisar conter SQL literal:

```ruby
def change
  execute <<~SQL
    CREATE VIEW active_users AS
    SELECT * FROM users WHERE active = true
  SQL
end
```

O conteúdo de `execute` é emitido como escrito, sem consultar nem alterar o banco durante a geração. Ele não retorna resultados de consultas para decisões Ruby. Sua compatibilidade com o banco de destino é responsabilidade de quem escreve a migration.

### Consultas que dependem de dados

Métodos como `select_value`, `select_values`, `select_all`, `select_rows`, `select_one`, `exec_query` e `exec_select` exigem um banco real e são rejeitados com `UnsupportedOperationError`, tanto diretamente na migration quanto por `connection`.

Por exemplo, `connection.select_value("SELECT COUNT(*) FROM artigos WHERE categoria IS NULL")` não pode fornecer um resultado durante a compilação offline. Use SQL explícito para a operação de dados, quando isso representar a regra desejada, ou um script separado de manutenção revisado pelo DBA. Mudar apenas o nome da chamada para `execute` não resolve uma condição Ruby que depende do valor consultado.

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

1. Gere os arquivos para o banco de destino.
2. Revise cada `<versão>_<nome>.sql`.
3. Execute os arquivos SQL em ordem crescente de versão, em um cliente configurado para interromper em caso de erro.
4. Valide as alterações e o registro das versões em `schema_migrations`.

Cada arquivo contém as operações da migration e, ao final, o `INSERT` da versão. A tabela de controle deve existir e a versão ainda não deve estar registrada. O script não adiciona uma transação global: o registro final só deve ser executado se todas as operações anteriores tiverem sucesso. A gem não gera rollback.

## Funcionamento e limitações

A classe da migration é carregada como Ruby. O `MigrationSandbox` intercepta as chamadas da DSL suportada, registra operações em memória e as encaminha ao compilador do dialeto escolhido. O `PackageWriter` grava um único arquivo SQL por migration e dialeto.

O compilador não consulta dados da aplicação para decidir o que gerar. Migrations que dependem de modelos ou consultas, como as abaixo, ficam fora do fluxo offline suportado:

```ruby
Order.where(status: nil).update_all(status: "pending")

if Order.count > 1_000_000
  add_index :orders, :created_at
end
```

Trate essas alterações como scripts explícitos de manutenção de dados ou SQL revisado pelo DBA. Durante a geração, a gem substitui temporariamente o gerenciador de conexões ActiveRecord no contexto de execução atual. A obtenção ou criação de conexões por modelos é bloqueada com `UnsupportedOperationError`; o gerenciador anterior é restaurado mesmo em caso de falha. Isso também vale durante o carregamento dos arquivos de migration e do snapshot.

Essa proteção não é um isolamento completo de Ruby: conexões ou pools guardados previamente, clientes de banco externos ao ActiveRecord, novas threads, código que substitua o gerenciador e efeitos colaterais arbitrários ficam fora do bloqueio. A inicialização da aplicação Rails ocorre antes da proteção. Compile apenas migrations confiáveis e não use esses caminhos para acessar bancos durante a geração.

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

## Benchmark da geração

Execute `bundle exec ruby benchmark/generation.rb` para gerar 600 arquivos temporários (120 migrations, 20 colunas por tabela, cinco dialetos), medir tempo e alocações e remover os arquivos ao terminar. Use `MIGRATIONS=240` para variar o volume. A medição cobre a compilação e a escrita dos arquivos, sem conexão com bancos.
