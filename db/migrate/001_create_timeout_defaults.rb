class CreateTimeoutDefaults < ActiveRecord::Migration
  def change
    create_table :state_timeout_defaults do |t|
      t.string :state, null: false
      t.integer :timeout, null: false
      t.timestamps null: false
    end

    create_table :time_limit_defaults do |t|
      t.references :tracker, null: false
      t.integer :hours, null: false
      t.timestamps null: false
    end
  end
end
