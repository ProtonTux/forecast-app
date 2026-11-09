class DropAddresses < ActiveRecord::Migration[8.1]
  def change
    drop_table :addresses, if_exists: true
  end
end
