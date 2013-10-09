require 'active_support/concern'

module ApiDsl
  extend ActiveSupport::Concern

  def validate_response(model, json, expect={})
    message_table(model).fields.each do |name, field|

      # refactor: pass exclusions, and figure out which are valid to not be there
      next if name.to_s == "guid"
      next if name.to_s == "default_space_url"
      next if name.to_s == "space_url"

      json.should have_key name.to_s
      if expect.has_key? name.to_sym
        json[name.to_s].should == expect[name.to_sym]
      end
    end
  end

  def standard_list_response json, model
    standard_paginated_response_format? parsed_response
    parsed_response["resources"].each do |resource|
      standard_entity_response resource, model
    end
  end

  def standard_entity_response json, model, expect={}
    standard_metadata_response_format? json["metadata"]
    validate_response model, json["entity"], expect
  end

  def standard_paginated_response_format? json
    validate_response VCAP::RestAPI::PaginatedResponse, json
  end

  def standard_metadata_response_format? json
    validate_response VCAP::RestAPI::MetadataMessage, json
  end

  def message_table model
    return model if model.respond_to? :fields
    "VCAP::CloudController::#{model.to_s.capitalize.pluralize}Controller::ResponseMessage".constantize
  end

  def parsed_response
    parse(response_body)
  end

  module ClassMethods

    def api_version
      "/v2"
    end

    def standard_model_object model
      root = "#{api_version}/#{model.to_s.pluralize}"
      get root do
        example_request "List all #{model.to_s.pluralize.capitalize}" do
          standard_list_response parsed_response, model
        end
      end

      get "#{root}/:guid" do
        example_request "Retrieve a Particular #{model.to_s.capitalize}" do
          standard_entity_response parsed_response, model
        end
      end

      delete "#{root}/:guid" do
        example_request "Delete a Particular #{model.to_s.capitalize}" do
          status.should == 204
        end
      end
    end

    def standard_parameters
      request_parameter :limit, "Maximum number of results to return"
      request_parameter :offset, "Offset from which to start iteration"
      request_parameter :'urls_only', "If 1, only return a list of urls; do not expand metadata or resource attributes"
      request_parameter :'inline-relations-depth', "0 - don't inline any relations and return URLs.  Otherwise, inline to depth N."
    end

    def request_parameter(name, description, options = {})
      parameter name, description, options
      metadata[:request_parameters] ||= []
      metadata[:request_parameters].push(options.merge(:name => name.to_s, :description => description))
    end

    def field(name, description = "", options = {})
      parameter name, description, options
      metadata[:fields] ||= []
      metadata[:fields].push(options.merge(:name => name.to_s, :description => description))
    end

    def authenticated_request
      header "AUTHORIZATION", :admin_auth_header
    end

    #def header(key, value, replacement="")
    #  metadata[:display_headers]
    #end

    # refactor this, duplicated with the instance methods above, sorry!
    def message_table model
      model if model.respond_to? :fields
      "VCAP::CloudController::#{model.to_s.capitalize.pluralize}Controller::ResponseMessage".constantize
    end
  end
end
