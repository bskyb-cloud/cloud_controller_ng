module VCAP::CloudController

  # This controller is an experiment breaking away from the old
  # cloudcontroller metaprogramming. We manually generate the JSON
  # expected by CFoundry and CF.
  class ServiceBrokersController < RestController::Base
    post '/v2/service_brokers', :create
    def create
      raise NotAuthorized unless roles.admin?

      broker = Models::ServiceBroker.new(Yajl::Parser.parse(body))
      broker.save

      resource_url = "#{self.class.path}/#{broker.guid}"

      status = HTTP::CREATED
      headers = {"Location" => resource_url}

      body = {
        metadata: {
          guid: broker.guid,
          url: resource_url
        },
        entity: {
          name: broker.name,
          broker_url: broker.broker_url
        }
      }

      [status, headers, body.to_json]
    end

    def self.translate_validation_exception(e, _)
      if e.errors.on(:name) && e.errors.on(:name).include?(:unique)
        Errors::ServiceBrokerNameTaken.new(e.model.name)
      elsif e.errors.on(:broker_url) && e.errors.on(:broker_url).include?(:unique)
        Errors::ServiceBrokerUrlTaken.new(e.model.broker_url)
      else
        Errors::ServiceBrokerInvalid.new(e.errors.full_messages)
      end
    end

    get '/v2/service_brokers', :enumerate
    def enumerate
      raise NotAuthorized unless roles.admin?

      q = params['q']
      if q && q.start_with?('name:')
        filter = { :name => q.split(':')[1] }
      else
        filter = {}
      end

      status = HTTP::OK
      headers = {}
      brokers = Models::ServiceBroker.filter(filter)

      body = {
        'total_results' => brokers.count,
        'total_pages' => 1,
        'prev_url' => nil,
        'next_url' => nil,
      }
      body['resources'] = brokers.map do |broker|
        {
          'metadata' => {
            'guid' => broker.guid,
            # Normal restcontroller behavior includes a url
            #'url' => 'someurl',
            'created_at' => broker.created_at,
            'updated_at' => broker.updated_at,
          },
          'entity' => {
            'name' => broker.name,
            'broker_url' => broker.broker_url,
          }
        }
      end

      [status, headers, body.to_json]
    end

    delete '/v2/service_brokers/:guid', :delete
    def delete(guid)
      raise NotAuthorized unless roles.admin?

      broker = Models::ServiceBroker.find(:guid => guid)
      return HTTP::NOT_FOUND unless broker
      broker.destroy
      HTTP::NO_CONTENT
    end

    private
  end
end
