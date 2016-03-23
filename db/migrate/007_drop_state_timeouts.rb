class DropStateTimeouts < ActiveRecord::Migration
  def change
    drop_table :state_timeout_defaults
  end
end
