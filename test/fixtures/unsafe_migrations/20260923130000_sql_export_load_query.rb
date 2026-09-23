class SqlExportLoadQuery < ActiveRecord::Migration[8.0]
  ActiveRecord::Base.connection_pool

  def change
    add_column :articles, :category, :string
  end
end
