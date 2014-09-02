require "cloud_controller/dea/client"

module VCAP::CloudController
  class Route < Sequel::Model
    class InvalidDomainRelation < VCAP::Errors::InvalidRelation; end
    class InvalidAppRelation < VCAP::Errors::InvalidRelation; end

    many_to_one :domain
    many_to_one :space, after_set: :validate_changed_space

    many_to_many :apps,
      before_add:   :validate_app,
      after_add:    :mark_app_routes_changed,
      after_remove: :mark_app_routes_changed

    add_association_dependencies apps: :nullify

    export_attributes :host, :host_uniqueness, :host_uniqueness2, :domain_guid, :space_guid
    import_attributes :host, :host_uniqueness, :host_uniqueness2, :domain_guid, :space_guid, :app_guids

    def fqdn
      host.empty? ? domain.name : "#{host}.#{domain.name}"
    end

    def as_summary_json
      {
        guid:   guid,
        host:   host,
        domain: {
          guid: domain.guid,
          name: domain.name
        }
      }
    end

    def organization
      space.organization if space
    end

    def before_create
      super
      if (self.host =~ /\[index\]/)
        uniqueness1 = host.downcase
        uniqueness1.gsub!(/\[index\]/, '*')
        uniqueness1.gsub!(/\d+/, '*')
        self.host_uniqueness = uniqueness1
      end
      if ( self.host =~ /\d+/ )
        uniqueness2 = host.downcase
        uniqueness2.gsub!(/\[index\]/, '*')
        uniqueness2.gsub!(/\d+/, '*')
        self.host_uniqueness2 = uniqueness2
      end
    end
    
    def validate
      validates_presence :domain
      validates_presence :space

      errors.add(:host, :presence) if host.nil?

      validates_format   /^([\w\-\[\]]+)$/, :host if (host && !host.empty?)
      validates_unique   [:host, :domain_id]

      validate_index_uniqueness

      validate_domain
      validate_total_routes
    end
    
    def validate_index_uniqueness
      if self.host_uniqueness != ""
        validates_unique   [:host_uniqueness, :domain_id]
      end
      
      if (self.host =~ /\[index\]/)
        uniqueness = self.host.downcase
        uniqueness.gsub!(/\[index\]/, '*')
        uniqueness.gsub!(/\d+/, '*')
        routes = Route.find(:host_uniqueness2 => uniqueness, :domain_id => domain_id)
        unless routes.nil? then
          errors.add(:host_uniqueness, "Conflict with existing hostname #{routes.fqdn}")
        end
      end
      
      if (self.host =~ /\d+/)
        uniqueness = self.host.downcase
        uniqueness.gsub!(/\[index\]/, '*')
        uniqueness.gsub!(/\d+/, '*')
        routes = Route.find(:host_uniqueness => uniqueness, :domain_id => domain_id)
        unless routes.nil? then
          errors.add(:host_uniqueness, "Conflict with existing hostname #{routes.fqdn}")
        end
      end      
    end 

    def validate_app(app)
      return unless (space && app && domain)

      unless app.space == space
        raise InvalidAppRelation.new(app.guid)
      end

      unless domain.usable_by_organization?(space.organization)
        raise InvalidDomainRelation.new(domain.guid)
      end
    end

    def validate_changed_space(new_space)
      apps.each{ |app| validate(app) }
      domain && domain.addable_to_organization!(new_space.organization)
    end

    def self.user_visibility_filter(user)
      orgs = Organization.filter(Sequel.or(
        managers: [user],
        auditors: [user],
      ))

      spaces = Space.filter(Sequel.or(
        developers:   [user],
        auditors:     [user],
        managers:     [user],
        organization: orgs,
      ))

      { :space => spaces }
    end

    def in_suspended_org?
      space.in_suspended_org?
    end

    private

    def around_destroy
      loaded_apps = apps
      super

      loaded_apps.each do |app|
        mark_app_routes_changed(app)
      end
    end

    def mark_app_routes_changed(app)
      app.mark_routes_changed
    end

    def validate_domain
        errors.add(:domain, :invalid_relation) if !valid_domain
    end

    def valid_domain
      return true unless domain

      if (domain.shared? && !host.present?) ||
        (space && !domain.usable_by_organization?(space.organization))
        return false
      end

      true
    end

    def validate_total_routes
      return unless new? && space

      space_routes_policy = MaxRoutesPolicy.new(space.space_quota_definition, SpaceRoutes.new(space))
      org_routes_policy   = MaxRoutesPolicy.new(space.organization.quota_definition, OrganizationRoutes.new(space.organization))

      if space.space_quota_definition && !space_routes_policy.allow_more_routes?(1)
        errors.add(:space, :total_routes_exceeded)
      end

      if !org_routes_policy.allow_more_routes?(1)
        errors.add(:organization, :total_routes_exceeded)
      end
    end
  end
end
