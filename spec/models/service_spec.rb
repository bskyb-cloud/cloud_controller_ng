# Copyright (c) 2009-2012 VMware, Inc.

require File.expand_path("../spec_helper", __FILE__)

module VCAP::CloudController
  describe VCAP::CloudController::Models::Service do
    it_behaves_like "a CloudController model", {
      :required_attributes  => [:label, :provider, :url, :description, :version],
      :unique_attributes    => [:label, :provider],
      :sensitive_attributes => :crypted_password,
      :stripped_string_attributes => [:label, :provider],
      :one_to_zero_or_more   => {
        :service_plans      => lambda { |_| Models::ServicePlan.make }
      }
    }

    describe 'when destroying' do
      let!(:service) { VCAP::CloudController::Models::Service.make }
      subject { service.destroy }

      it "doesn't remove the associated ServiceAuthToken" do
        # XXX services don't always have a token, unlike what the fixture implies
        expect {
          subject
        }.to_not change {
          VCAP::CloudController::Models::ServiceAuthToken.count(
            :label => service.label,
            :provider => service.provider,
          )
        }
      end
    end
  end
end
