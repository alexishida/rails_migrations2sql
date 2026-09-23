class SqlExportPopulateArticles < ActiveRecord::Migration[8.0]
  def change
    execute "UPDATE articles SET category = 'general' WHERE category IS NULL"
    reversible do |direction|
      direction.up { add_index :articles, :category }
      direction.down { raise "Rollback must not be evaluated" }
    end
  end
end
