class CreateAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :addresses do |t|
      t.string :zip_code
      t.string :country_code
      t.string :city
      t.string :region_state
      t.decimal :latitude
      t.decimal :longitude
      t.string :timezone
      t.string :geocoding_source
      t.datetime :geocoded_at

      t.timestamps
    end
  end
end
