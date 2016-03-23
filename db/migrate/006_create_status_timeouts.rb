class CreateStatusTimeouts < ActiveRecord::Migration
  def change
    create_table :status_timeout_defaults do |t|
      t.integer :status, null: false
      t.integer :timeout, null: false
      t.timestamps null: false
    end
  end
end
