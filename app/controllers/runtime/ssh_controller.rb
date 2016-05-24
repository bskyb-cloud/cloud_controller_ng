require 'httpclient'
require 'uri'

module VCAP::CloudController
  class SshController < RestController::ModelController
    path_base 'apps'
    model_class_name :App

    get "#{path_guid}/instances/:instance_id/ssh", :ssh
    def ssh(guid, instance, opts={})
      app = find_guid_and_validate_access(:read, guid)

      response = Dea::Client.ssh_instance(app, instance.to_i)

      logger.debug "Getting SSH info #{Yajl::Encoder.encode(response)}"
      [HTTP::OK, Yajl::Encoder.encode(response)]
    end
  end
end
