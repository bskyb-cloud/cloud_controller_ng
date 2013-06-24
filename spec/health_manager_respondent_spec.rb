# Copyright (c) 2009-2012 VMware, Inc.

require File.expand_path("../spec_helper", __FILE__)
require "cloud_controller/health_manager_respondent"

module VCAP::CloudController
  describe HealthManagerRespondent do
    shared_examples "common test for all health manager respondents" do
      before do
        dea_client.stub(:stop_instances)
        dea_client.stub(:stop)
        dea_client.stub(:start_instances_with_message)
      end

      it "CC subscribes to the Health Manager messages" do
        mbus.should_receive(:subscribe).with("cloudcontrollers.hm.requests.ng", :queue => "cc")
        process_hm_request
      end
    end

    before { mbus.stub(:subscribe).with(anything, anything) }

    let(:mbus) { double("mock message bus") }
    let(:dea_client) { double("mock dea client", :message_bus => mbus) }
    let(:respondent) do
      HealthManagerRespondent.new(
        config.merge(:message_bus => mbus, :dea_client => dea_client)
      )
    end

    let(:app) do
      Models::App.make(
        :instances => 2, :state => 'STARTED', :package_hash => "SOME_HASH", :package_state => "STAGED"
      ).save
    end

    let(:payload) do
      {
        :droplet        => app.guid,
        :op             => op,
        :last_updated   => app.updated_at,
        :version        => app.version,
        :indices        => [1],
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
          let(:app) { Models::App.make(:instances => 2).save }

          it "drops the request" do
            dea_client.should_not_receive(:start_instances_with_message)
            mbus.should_not_receive(:publish).with(/^dea.+.start$/, anything)
            process_hm_request
          end
        end

        context "when the times mismatch" do
          before { app.updated_at = Time.now - 86400 }

          it "drops the request" do
            dea_client.should_not_receive(:start_instances_with_message)
            mbus.should_not_receive(:publish).with(/^dea.+.start$/, anything)
            process_hm_request
          end
        end

        context "when the payload's last_updated field is nil" do
          before do
            payload[:last_updated] = nil
          end

          it "still tries to start the instance" do
            dea_client.should_receive(:start_instances_with_message).with(respond_with(:guid => app.guid), [1], {})
            process_hm_request
          end
        end

        context "when the versions mismatch" do
          before { app.version = 'deadbeaf-0' }

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
            :last_updated   => app.updated_at,
            :version        => app.version,
            :instances      => instances,
          }
        end

        let(:app) do
          Models::App.make(
            :instances => 2, :state => 'STOPPED'
          ).save
        end

        it_should_behave_like "common test for all health manager respondents"

        it "sends a stop request to dea" do
          dea_client.should_receive(:stop_instances).with(
            respond_with(:guid => app.guid),
            [2],
          )

          process_hm_request
        end

        context "with a runaway app (deleted but still running)" do
          let(:instances) { [1] }

          let(:app) { nil }

          let(:payload) do
            {
              :droplet        => "some-guid",
              :op             => op,
              :last_updated   => Time.new,
              :version        => "some-version",
              :instances      => instances,
            }
          end

          it "sends a stop request to dea" do
            dea_client.should_receive(:stop) do |new_app|
              expect(new_app.guid).to eq "some-guid"
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
            app.destroy
            dea_client.should_not_receive(:stop)
            process_hm_request
          end

          it "logs an error" do
            respondent.logger.should_receive(:error).with(/malformed/i, instance_of(Hash))
            process_hm_request
          end
        end

        shared_examples "health manager scales all the way down" do
          it "sends a stop request to the dea" do
            dea_client.should_receive(:stop) do |changed_app|
              reloaded_app = app.reload
              [:id, :guid, :state, :instances].each do |field|
                changed_app.send(field).should == reloaded_app.send(field)
              end
            end
            process_hm_request
          end
        end

        context "when health manager scales down to 0 instances" do
          let(:instances) { [0, 1] }
          before { dea_client.stub(:stop) }

          it_should_behave_like "health manager scales all the way down"

          context "and the CC has desired state of 2 running instances" do
            let(:app) do
              Models::App.make(
                :instances => 2, :state => 'STARTED',
                :package_hash => "SOME_HASH", :package_state => "STAGED"
              ).save
            end

            xit "does not act on HM's request" do
              dea_client.should_not_receive(:stop)
              process_hm_request
            end
          end
        end

        context "when health manager scales down to less than 0 instances" do
          let(:instances) { [0, 1, 2] }
          before { dea_client.stub(:stop) }

          it "logs an warning" do
            respondent.logger.should_receive(:warn).with(/negative/i, instance_of(Hash))
            process_hm_request
          end

          it_should_behave_like "health manager scales all the way down"
        end
      end
    end
  end
end
