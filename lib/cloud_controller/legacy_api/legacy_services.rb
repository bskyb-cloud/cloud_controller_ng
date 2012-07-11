# Copyright (c) 2009-2012 VMware, Inc.

require "services/api"

# NOTE: this will get refactored a bit as other methods get added
# and as we start adding other legacy protocol conversions.
module VCAP::CloudController
  class LegacyService < LegacyApiBase
    include VCAP::CloudController::Errors
    SERVICE_TOKEN_KEY = "HTTP_X_VCAP_SERVICE_TOKEN"
    DEFAULT_PROVIDER = "core"
    LEGACY_API_USER_GUID = "legacy-api"

    def initialize(config, logger, request, service_auth_token = nil)
      @service_auth_token = service_auth_token
      super(config, logger, request)
    end

    def enumerate
      resp = default_app_space.service_instances.map do |svc_instance|
        legacy_service_encoding(svc_instance)
      end

      Yajl::Encoder.encode(resp)
    end

    def create_offering
      req = VCAP::Services::Api::ServiceOfferingRequest.decode(request.body)
      logger.debug("Create service request: #{req.extract.inspect}")

      (label, version) = req.label.split("-")
      svc_attrs = {
        :label       => label,
        :provider    => DEFAULT_PROVIDER,
        :url         => req.url,
        :description => req.description,
        :version     => version,
        :acls        => req.acls,
        :timeout     => req.timeout,
        :info_url    => req.info_url,
        :active      => req.active
      }

      provider = DEFAULT_PROVIDER
      validate_access(label, provider)

      VCAP::CloudController::SecurityContext.current_user = self.class.legacy_api_user
      legacy_req = Yajl::Encoder.encode(svc_attrs)
      svc_api = VCAP::CloudController::Service.new(logger, legacy_req)
      (_, _, svc_resp) = svc_api.dispatch(:create)
      svc = Yajl::Parser.parse(svc_resp)

      svc_plan_attrs = {
        :service_guid => svc["metadata"]["guid"],
        :name => "default",
        :description => "default plan"
      }

      legacy_req = Yajl::Encoder.encode(svc_plan_attrs)
      svc_plan_api = VCAP::CloudController::ServicePlan.new(logger, legacy_req)
      svc_plan_api.dispatch(:create)

      empty_json
    rescue JsonMessage::ValidationError => e
      raise InvalidRequest
    end

    def validate_access(label, provider = DEFAULT_PROVIDER)
      svc_auth_token = Models::ServiceAuthToken.find(:label => label,
                                                     :provider => provider)

      unless (svc_auth_token &&
              svc_auth_token.token_matches?(service_auth_token))
        logger.warn("unauthorized service offering")
        raise NotAuthorized
      end
    end

    # Keep these here in the legacy api translation rather than polluting the
    # model/schema
    def self.synthesize_service_type(svc)
      case svc.label
      when /mysql/
        "database"
      when /postgresql/
        "database"
      when /redis/
        "key-value"
      when /mongodb/
        "key-value"
      else
        "generic"
      end
    end

    private

    def empty_json
      "{}"
    end

    def legacy_service_encoding(svc_instance)
      plan = svc_instance.service_plan
      {
        :name => svc_instance.name,
        :type => LegacyService.synthesize_service_type(plan.service),
        :vendor => plan.service.label,
        :version => plan.service.version,
        :tier => "free",
        :properties => [],
        :meta => {}
      }
    end

    def self.legacy_api_user
      user = Models::User.find(:guid => LEGACY_API_USER_GUID)
      if user.nil?
        user = Models::User.create(:guid => LEGACY_API_USER_GUID,
                                   :admin => true,
                                   :active => true)
      end
      user
    end

    def self.setup_routes
      controller.get "/services" do
        LegacyService.new(@config, logger, request).enumerate
      end

      controller.before "/services/v1/*" do
        @service_auth_token = env[SERVICE_TOKEN_KEY]
      end

      controller.post "/services/v1/offerings" do
        LegacyService.new(@config, logger, request, @service_auth_token).create_offering
      end
    end

    def self.controller
      VCAP::CloudController::Controller
    end

    setup_routes
    attr_accessor :request, :logger, :service_auth_token
  end
end
