class CreateBankHolidays < ActiveRecord::Migration
  def change
    create_table :bank_holidays do |t|
      t.date :holiday, null: false
      t.string :name, null: false
      t.string :notes, null: false
    end
  end
end
