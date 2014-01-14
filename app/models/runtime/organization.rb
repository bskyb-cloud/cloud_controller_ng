module VCAP::CloudController
  class Organization < Sequel::Model
    ORG_NAME_REGEX = /\A[[:alnum:][:punct:][:print:]]+\Z/.freeze
    class UnauthorizedAccessToPrivateDomain < RuntimeError; end

    one_to_many :spaces
    one_to_many :service_instances, dataset: -> { VCAP::CloudController::ServiceInstance.filter(space: spaces) }
    one_to_many :apps, dataset: -> { App.filter(space: spaces) }
    one_to_many :app_events, dataset: -> { VCAP::CloudController::AppEvent.filter(app: apps) }
    one_to_many :private_domains, key: :owning_organization_id
    one_to_many :service_plan_visibilities
    many_to_one :quota_definition
    one_to_many :domains,
                dataset: -> { VCAP::CloudController::Domain.filter(owning_organization_id: id).or(owning_organization_id: nil) },
                remover: ->(legacy_domain) { legacy_domain.destroy if legacy_domain.owning_organization_id == id },
                clearer: -> { remove_all_private_domains },
                adder: ->(legacy_domain) do
                  return unless legacy_domain.owning_organization_id
                  raise UnauthorizedAccessToPrivateDomain unless legacy_domain.owning_organization_id == id
                end

    add_association_dependencies spaces: :destroy,
      service_instances: :destroy,
      private_domains: :destroy,
      service_plan_visibilities: :destroy

    define_user_group :users
    define_user_group :managers, reciprocal: :managed_organizations
    define_user_group :billing_managers, reciprocal: :billing_managed_organizations
    define_user_group :auditors, reciprocal: :audited_organizations

    strip_attributes  :name

    default_order_by  :name

    export_attributes :name, :billing_enabled, :quota_definition_guid, :status
    import_attributes :name, :billing_enabled,
                      :user_guids, :manager_guids, :billing_manager_guids,
                      :auditor_guids, :private_domain_guids, :quota_definition_guid,
                      :status, :domain_guids

    def billing_enabled?
      billing_enabled
    end

    def before_create
      add_default_quota
      super
    end

    def validate
      validates_presence :name
      validates_unique   :name
      validate_only_admin_can_update(:billing_enabled)
      validate_only_admin_can_update(:quota_definition_id)
      validates_format ORG_NAME_REGEX, :name
    end

    def validate_only_admin_can_enable_on_new(field_name)
      if new? && !!public_send(field_name)
        require_admin_for(field_name)
      end
    end

    def validate_only_admin_can_update(field_name)
      if !new? && column_changed?(field_name)
        require_admin_for(field_name)
      end
    end

    def require_admin_for(field_name)
      unless VCAP::CloudController::SecurityContext.admin?
        errors.add(field_name, :not_authorized)
      end
    end

    def before_save
      super
      if column_changed?(:billing_enabled) && billing_enabled?
        @is_billing_enabled = true
      end
    end

    def after_save
      super
      # We cannot start billing events without the guid being assigned to the org.
      if @is_billing_enabled
        OrganizationStartEvent.create_from_org(self)
        # retroactively emit start events for services
        spaces.map(&:service_instances).flatten.each do |si|
          ServiceCreateEvent.create_from_service_instance(si)
        end
        spaces.map(&:apps).flatten.each do |app|
          AppStartEvent.create_from_app(app) if app.started?
        end
      end
    end

    def add_default_quota
      unless quota_definition_id
        self.quota_definition_id = QuotaDefinition.default.id
      end
    end

    def memory_remaining
      memory_used = apps_dataset.sum(Sequel.*(:memory, :instances)) || 0
      quota_definition.memory_limit - memory_used
    end

    def active?
      status == 'active'
    end

    def self.user_visibility_filter(user)
      Sequel.or(
        managers: [user],
        users: [user],
        billing_managers: [user],
        auditors: [user])
    end
  end
end
