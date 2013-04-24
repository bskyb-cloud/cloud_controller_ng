# Copyright (c) 2009-2012 VMware, Inc.

require File.expand_path("../spec_helper", __FILE__)
require "cloud_controller/health_manager_respondent"

module VCAP::CloudController
  describe HealthManagerRespondent do
    shared_examples "common test for all health manager respondents" do
      it "CC subscribes to the Health Mangager NATS" do
        mbus.should_receive(:subscribe).with("cloudcontrollers.hm.requests.ng", :queue => "cc")
        process_hm_request
      end
    end

    before { mbus.stub(:subscribe).with(anything, anything) }

    let(:app) { Models::App.make(:instances => 2).save }
    let(:mbus) { double("mock nats") }
    let(:dea_client) { double("mock dea client", :message_bus => mbus) }
    let(:respondent) do
      HealthManagerRespondent.new(
        config.merge(:message_bus => mbus, :dea_client => dea_client)
      )
    end
    let(:last_updated) { app.updated_at }
    let(:version) { app.version }
    let(:indices) { [1] }
    let(:payload) do
      {
        :droplet        => app.guid,
        :op             => op,
        :last_updated   => last_updated,
        :version        => version,
        :indices        => indices,
      }
    end

    subject(:process_hm_request) { respondent.process_hm_request(payload) }

    describe "#process_hm_request" do
      describe "on START request" do
        let(:op) { "START" }

        it_should_behave_like "common test for all health manager respondents"

        it "sends a start request to dea" do
          app.update(
            :state => "STARTED",
            :package_hash => "abc",
            :package_state => "STAGED",
          )

          dea_client.should_receive(:start_instances_with_message).with(
            # XXX: we should do something about this, like overriding
            # Sequel::Model#eql? or something that ignores the nanosecond
            # nonsense
            respond_with(:guid => app.guid),
            [1],
            {},
          )

          process_hm_request
        end

        context "when the app isn't started" do
          it "drops the request" do
            dea_client.should_not_receive(:start_instances_with_message)
            mbus.should_not_receive(:publish).with(/^dea.+.start$/, anything)
            process_hm_request
          end
        end

        context "when the times mismatch" do
          let(:last_updated) { Time.now - 86400 }
          it "drops the request" do
            dea_client.should_not_receive(:start_instances_with_message)
            mbus.should_not_receive(:publish).with(/^dea.+.start$/, anything)
            process_hm_request
          end
        end

        context "when the versions mismatch" do
          let(:version) { 'deadbeaf-0' }
          it "drops the request" do
            dea_client.should_not_receive(:start_instances_with_message)
            mbus.should_not_receive(:publish).with(/^dea.+.start$/, anything)
            process_hm_request
          end
        end

        context "when the app is flapping" do
          it "should send a start request indicating a flapping app" do
            app.update(
              :state => "STARTED",
              :package_hash => "abc",
              :package_state => "STAGED",
            )
            payload.merge!(:flapping => true)

            dea_client.should_receive(:start_instances_with_message).with(
              respond_with(:guid => app.guid),
              [1],
              :flapping => true,
            )

            process_hm_request
          end
        end
      end

      describe "on STOP request" do
        let(:instances) { [2] }
        let(:op) { "STOP" }
        let(:payload) do
          {
            :droplet        => app.guid,
            :op             => op,
            :last_updated   => last_updated,
            :version        => version,
            :instances        => instances,
          }
        end

        it_should_behave_like "common test for all health manager respondents" do
          before { dea_client.stub(:stop_instances) }
        end

        it "sends a stop request to dea" do
          dea_client.should_receive(:stop_instances).with(
            respond_with(:guid => app.guid),
            [2],
          )

          process_hm_request
        end

        context "when the timestamps mismatch" do
          let(:last_updated) { Time.now - 86400 }
          let(:instances) { [1] }
          it "drops the request" do
            dea_client.should_not_receive(:stop_instances)
            mbus.should_not_receive(:publish).with(/^dea.+.start$/, anything)
            process_hm_request
          end
        end

        context "with a runaway app" do
          let(:instances) { [1] }
          it "sends a stop request to dea" do
            app.destroy
            dea_client.should_receive(:stop) do |app|
              app.guid.should == app.guid
            end

            process_hm_request
          end
        end

        context "when the payload is malformed" do
          before { payload.delete(:droplet) }

          it "does not send a stop request to the dea" do
            dea_client.should_not_receive(:stop_instances)
            process_hm_request
          end

          it "does not stop any runway apps" do
            dea_client.should_not_receive(:stop)
            process_hm_request
          end

          it "logs an error" do
            respondent.logger.should_receive(:error).with(/malformed/i)
            process_hm_request
          end
        end
      end

      describe "on SPINDOWN request" do

        let(:op) { "SPINDOWN" }

        it_should_behave_like "common test for all health manager respondents"

        it "should drop the request if app already stopped" do
          app.update(
            :state => "STOPPED",
          )

          dea_client.should_not_receive(:stop)
          mbus.should_not_receive(:publish).with(
            "dea.stop",
            anything,
          )

          process_hm_request
        end

        it "should stop an app" do
          app.update(
            :state => "STARTED",
            :package_hash => "abc",
            :package_state => "STAGED",
          )

          dea_client.should_receive(:stop).with(
            respond_with(:guid => app.guid),
          )
          process_hm_request
        end

        it "should update the state of an app to stopped" do
          app.update(
            :state => "STARTED",
            :package_hash => "abc",
            :package_state => "STAGED",
          )

          dea_client.should_receive(:stop)
          process_hm_request

          app.reload.should be_stopped
        end
      end
    end
  end
end
