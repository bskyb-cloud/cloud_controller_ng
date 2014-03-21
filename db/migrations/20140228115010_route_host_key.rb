Sequel.migration do
  change do
    alter_table :routes do
      add_column :host_uniqueness, String
      add_column :host_uniqueness2, String
    end
  end
end