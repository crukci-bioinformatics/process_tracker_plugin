class CreateProjectStateReports < ActiveRecord::Migration
  def change
    create_table :project_state_reports do |t|
      t.integer :ordering, null: false
      t.string :name, null: false
      t.string :view, null: false
      t.string :dateview, null: false
      t.boolean :want_interval
      t.timestamps null: false
    end
  end
end
