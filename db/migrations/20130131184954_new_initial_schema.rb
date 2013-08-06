# Copyright (c) 2009-2012 VMware, Inc.

# This is a squash of all previous migrations for ccng.  This needed to be done
# to support mysql as a database option for ccng.
#
# As the previous set of migrations evolved, they ended up droping columns
# as the schema was changed  to support new/changing feature sets. However,
# some of these columns had constraints, inluding foreign key constraints.
# While sqlite and postgress will allow you to drop a column with an existing
# foreign key constraint, mysql will not.  The only way to drop such a column
# when running against  mysql is to explicitly drop the constraint first.
# However, the standard usage of the sequel migations is to just accept
# the default constraint name generated by the DDL, so dropping the constraint
# by name is not possible without reverse engineering the naming conventions
# of the sequel migrations.  Obviouslly, that would be very brittle.
#
# This reset of the migrations explicitly names every constraint in order
# to support these sort of changes on mysql, pg, and sqlite going
# forward.
#
# This is the approach recommended in
# http://code.google.com/p/ruby-sequel/issues/detail?id=284

Sequel.migration do

  change do
    # rather than creating different tables for each type of events, we're
    # going to denormalize them into one table.
    #
    # We don't use foreign keys here because the objects may get deleted after
    # the billing records are generated, and that should be allowed.
    create_table :billing_events do
      VCAP::Migration.common(self, :be)
      DateTime :timestamp, :null => false
      String :kind, :null => false
      String :organization_guid, :null => false
      String :organization_name, :null => false
      String :space_guid
      String :space_name
      String :app_guid
      String :app_name
      String :app_plan_name
      String :app_run_id
      Integer :app_memory
      Integer :app_instance_count
      String :service_instance_guid
      String :service_instance_name
      String :service_guid
      String :service_label
      String :service_provider
      String :service_version
      String :service_plan_guid
      String :service_plan_name

      index :timestamp
    end

    create_table :quota_definitions do
      VCAP::Migration.common(self, :qd)

      String :name, :null => false, :unique => true, :case_insensitive => true
      Boolean :non_basic_services_allowed, :null => false
      Integer :total_services, :null => false
      Integer :memory_limit, :null => false

      index :name, :unique => true
    end

    create_table :service_auth_tokens do
      VCAP::Migration.common(self, :sat)

      String :label,         :null => false, :case_insensitive => true
      String :provider,      :null => false, :case_insensitive => true
      String :token,         :null => false

      index [:label, :provider], :unique => true
    end

    create_table :services do
      VCAP::Migration.common(self)

      String :label,       :null => false, :case_insensitive => true
      String :provider,    :null => false, :case_insensitive => true
      String :url,         :null => false
      String :description, :null => false
      String :version,     :null => false

      String  :info_url
      String  :acls
      Integer :timeout
      Boolean :active, :default => false

      index :label
      index [:label, :provider], :unique => true
    end

    create_table :organizations do
      VCAP::Migration.common(self)
      String :name, :null => false, :case_insensitive => true
      TrueClass :billing_enabled, :null => false, :default => false
      Integer :quota_definition_id, :null => false
      foreign_key [:quota_definition_id], :quota_definitions, :name => :fk_organizations_quota_definition_id

      index :name, :unique => true
    end

    create_table :frameworks do
      VCAP::Migration.common(self)

      String :name,        :null => false, :case_insenstive => true
      String :description, :null => false
      String :internal_info, :null => false, :size => 2048

      index :name, :unique => true
    end

    create_table :runtimes do
      VCAP::Migration.common(self)

      String :name,        :null => false, :case_insensitive => true
      String :description, :null => false
      String :internal_info, :null => false, :size => 2048

      index :name, :unique => true
    end

    create_table :service_plans do
      VCAP::Migration.common(self)

      String :name,        :null => false, :case_insensitive => true
      String :description, :null => false
      TrueClass :free, :null => false
      Integer :service_id, :null => false
      foreign_key [:service_id], :services, :name => :fk_service_plans_service_id

      index [:service_id, :name], :unique => true
    end

    create_table :domains do
      VCAP::Migration.common(self)

      String :name, :null => false, :case_insensitive => true
      TrueClass :wildcard, :default => true, :null => false
      Integer :owning_organization_id
      foreign_key [:owning_organization_id], :organizations, :name => :fk_domains_owning_organization_id

      index :name, :unique => true
    end

    create_table :spaces do
      VCAP::Migration.common(self)

      String :name, :null => false, :case_insensitive => true
      Integer :organization_id, :null => false
      foreign_key [:organization_id], :organizations, :name => :fk_spaces_organization_id

      index [:organization_id, :name], :unique => true
    end

    create_table :apps do
      VCAP::Migration.common(self)

      String :name, :null => false, :case_insensitive => true

      # Do the bare miminum for now.  We'll migrate this to something
      # fancier later if we need it.
      Boolean :production, :default => false

      # environment provided by the developer.
      # does not include environment from service
      # bindings.  those get merged from the bound
      # services
      String :environment_json

      # quota settings
      #
      # FIXME: these defaults are going to move out of here and into
      # the upper layers so that they are more easily run-time configurable
      #
      # This *MUST* be moved because we have to know up at the controller
      # what the actual numbers are going to be so that we can
      # send the correct billing events to the "money maker"
      Integer :memory,           :default => 256
      Integer :instances,        :default => 0
      Integer :file_descriptors, :default => 16384
      Integer :disk_quota,       :default => 2048

      # app state
      String :state,             :null => false, :default => "STOPPED"

      # package state
      String :package_state,     :null => false, :default => "PENDING"
      String :package_hash

      String :droplet_hash
      String :version
      String :metadata, :default => "{}", :null => false
      String :buildpack

      Integer :space_id, :null => false
      Integer :runtime_id, :null => false
      Integer :framework_id, :null => false

      foreign_key [:space_id],     :spaces,     :name => :fk_apps_space_id
      foreign_key [:runtime_id],   :runtimes,   :name => :fk_apps_runtime_id
      foreign_key [:framework_id], :frameworks, :name => :fk_apps_framework_id

      index :name
      index [:space_id, :name], :unique => true
    end

    create_table :domains_organizations do
      Integer :domain_id, :null => false
      foreign_key [:domain_id], :domains, :name => :fk_domains_organizations_domain_id

      Integer :organization_id, :null => false
      foreign_key [:organization_id], :organizations, :name => :fk_domains_organizations_organization_id

      index [:domain_id, :organization_id], :unique => true
    end

    create_table :domains_spaces do
      Integer :space_id, :null => false
      foreign_key [:space_id], :spaces, :name => :fk_domains_spaces_space_id

      Integer :domain_id, :null => false
      foreign_key [:domain_id], :domains, :name => :fk_domains_spaces_domain_id

      index [:space_id, :domain_id], :unique => true
    end

    create_table :routes do
      VCAP::Migration.common(self)

      String :host, :null => false, :default => "", :case_insensitive => true

      Integer :domain_id, :null => false
      foreign_key [:domain_id], :domains, :name => :fk_routes_domain_id

      Integer :space_id, :null => false
      foreign_key [:space_id], :spaces, :name => :fk_routes_space_id

      index [:host, :domain_id], :unique => true
    end

    create_table :service_instances do
      VCAP::Migration.common(self, :si)

      String :name, :null => false, :case_insensitive => true
      String :credentials, :null => false, :size => 2048
      String :gateway_name
      String :gateway_data, :size => 2048

      Integer :space_id, :null => false
      foreign_key [:space_id], :spaces, :name => :service_instances_space_id

      Integer :service_plan_id, :null => false
      foreign_key [:service_plan_id], :service_plans, :name => :service_instances_service_plan_id

      index :name
      index [:space_id, :name], :unique => true #, :name => :space_id_name_index
    end

    create_table :users do
      VCAP::Migration.common(self)

      Integer :default_space_id
      foreign_key [:default_space_id], :spaces, :name => :fk_users_default_space_id

      Boolean :admin,  :default => false
      Boolean :active, :default => false
    end

    create_table :apps_routes do
      Integer :app_id, :null => false
      foreign_key [:app_id], :apps, :name => :fk_apps_routes_app_id

      Integer :route_id, :null => false
      foreign_key [:route_id], :routes, :name => :fk_apps_routes_route_id

      index [:app_id, :route_id], :unique => true
    end

    # Organization permissions
    [:users, :managers, :billing_managers, :auditors].each do |perm|
      VCAP::Migration.create_permission_table(self, :organization, :org, perm)
    end

    create_table(:service_bindings) do
      VCAP::Migration.common(self, :sb)

      String :credentials, :null => false, :size => 2048
      String :binding_options

      String :gateway_name, :null => false, :default => ''
      String :configuration
      String :gateway_data

      Integer :app_id, :null => false
      foreign_key [:app_id], :apps, :name => :fk_service_bindings_app_id

      Integer :service_instance_id, :null => false
      foreign_key [:service_instance_id], :service_instances, :name => :fk_service_bindings_service_instance_id

      index [:app_id, :service_instance_id], :unique => true
    end

    # App Space permissions
    [:developers, :managers, :auditors].each do |perm|
      VCAP::Migration.create_permission_table(self, :space, :space, perm)
    end
  end
end
