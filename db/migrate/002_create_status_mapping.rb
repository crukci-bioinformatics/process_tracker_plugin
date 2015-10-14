class CreateStatusMapping < ActiveRecord::Migration
  def change
    create_table :status_state_mappings do |t|
      t.integer :status, null: false
      t.string :state, null: false
      t.timestamps null: false
    end
  end
end
