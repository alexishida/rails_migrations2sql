class SqlExportCreateArticles < ActiveRecord::Migration[8.0]
  def change
    create_table :articles do |table|
      table.string :category
    end
  end

  def down
    select_value("SELECT COUNT(*) FROM articles")
    raise "Rollback must not be evaluated"
  end
end
