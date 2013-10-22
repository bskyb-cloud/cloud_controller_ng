require "spec_helper"

module VCAP::CloudController
  describe AppObserver do
    let(:message_bus) { CfMessageBus::MockMessageBus.new }
    let(:stager_pool) { double(:stager_pool) }
    let(:dea_pool) { double(:dea_pool) }
    let(:config_hash) { {:config => 'hash'} }
    let(:blobstore_url_generator) { double }

    before do
      DeaClient.configure(config_hash, message_bus, dea_pool, blobstore_url_generator)
      AppObserver.configure(config_hash, message_bus, stager_pool)
    end

    describe ".run" do
      it "registers subscriptions for dea_pool" do
        stager_pool.should_receive(:register_subscriptions)
        AppObserver.run
      end
    end

    describe ".deleted" do
      let(:app) { AppFactory.make droplet_hash: nil, package_hash: nil }

      it "stops the application" do
        AppObserver.deleted(app)
        expect(message_bus).to have_published_with_message("dea.stop", droplet: app.guid)
      end

      context "when the app has a droplet" do
        before { app.droplet_hash = "abcdef" }

        it "enqueue a jobs to delete the buildpack cache" do
          expect { AppObserver.deleted(app) }.to change {
            Delayed::Job.count
          }.by(1)

          job = Delayed::Job.last
          expect(job.handler).to include(app.guid)
          expect(job.handler).to include("buildpack_cache_blobstore")
          expect(job.queue).to eq("cc-generic")
          expect(job.guid).not_to be_nil
        end


      end

      context "when the app has a package uploaded" do
        before { app.package_hash = "abcdef" }

        it "deletes the app package" do
          expect { AppObserver.deleted(app) }.to change {
            Delayed::Job.count
          }.by(1)

          job = Delayed::Job.last
          expect(job.handler).to include(app.guid)
          expect(job.handler).to include("package_blobstore")
          expect(job.queue).to eq("cc-generic")
          expect(job.guid).not_to be_nil
        end
      end
    end

    describe ".updated" do
      let(:package_hash) { "bar" }
      let(:needs_staging) { false }
      let(:started_instances) { 1 }
      let(:stager_task) { double(:stager_task) }

      let(:app) do
        double(:app,
          :last_stager_response= => nil,
          :needs_staging? => needs_staging,
          :instances => 1,
          :guid => "foo",
          :package_hash => package_hash
        )
      end

      subject { AppObserver.updated(app) }

      before do
        AppStagerTask.stub(:new).
          with(config_hash,
          message_bus,
          app,
          stager_pool,
          instance_of(CloudController::BlobstoreUrlGenerator)

        ).and_return(stager_task)

        stager_task.stub(:stage) do |&callback|
          callback.call(:started_instances => started_instances)
        end

        app.stub(previous_changes: changes)

        DeaClient.stub(:start)
        DeaClient.stub(:stop)
        DeaClient.stub(:change_running_instances)
      end

      shared_examples_for(:stages_if_needed) do
        context "when the app needs staging" do
          let(:needs_staging) { true }

          context "when the app package hash is nil" do
            let(:package_hash) { nil }

            it "raises" do
              expect {
                subject
              }.to raise_error(Errors::AppPackageInvalid)
            end
          end

          context "when the app package hash is blank" do
            let(:package_hash) { '' }

            it "raises" do
              expect {
                subject
              }.to raise_error(Errors::AppPackageInvalid)
            end
          end

          context "when the app package is valid" do
            let(:package_hash) { 'abc' }
            let(:started_instances) { 1 }

            it "should make a task and stage it" do
              stager_task.should_receive(:stage) do |&callback|
                callback.call(:started_instances => started_instances)
                "stager response"
              end

              app.should_receive(:last_stager_response=).with("stager response")

              subject
            end
          end
        end

        context "when staging is not needed" do
          let(:needs_staging) { false }

          it "should not make a stager task" do
            AppStagerTask.should_not_receive(:new)
            subject
          end
        end
      end

      shared_examples_for(:sends_droplet_updated) do
        it "should send droplet updated message" do
          #health_manager_client = CloudController::DependencyLocator.instance.health_manager_client
          #health_manager_client.should_receive(:notify_app_updated).with("foo")

          subject
        end
      end

      context "when the state of the app changes" do
        context "from STOPPED to STARTED" do
          context "and the app needs to be restaged" do
            it "sends message to stage app"
          end
        end
        context "from STARTED to STOPPED" do
          it "sends out message to stop the app"
        end
      end

      context "when the desired instance count changes" do
        context "by increasing" do
          it "sends out messages to start more instances"
        end

        context "by decreasing" do
          it "sends out messages to stop instances"
        end
      end

      context "when the state is changed" do
        let(:changes) { { :state => "anything" } }

        context "when the app is started" do
          let(:needs_staging) { true }

          before do
            app.stub(:started?) { true }
          end

          it_behaves_like :stages_if_needed
          it_behaves_like :sends_droplet_updated

          it "should start the app with specified number of instances" do
            DeaClient.should_receive(:start).with(app, :instances_to_start => app.instances - started_instances)
            subject
          end
        end

        context "when the app is not started" do
          before do
            app.stub(:started?) { false }
          end

          it_behaves_like :sends_droplet_updated

          it "should stop the app" do
            DeaClient.should_receive(:stop).with(app)
            subject
          end
        end
      end

      context "when the instances count is changed" do
        let(:changes) { { :instances => [5, 2] } }

        context "when the app is started" do
          before do
            app.stub(:started?) { true }
          end

          it_behaves_like :stages_if_needed
          it_behaves_like :sends_droplet_updated

          it 'should change the running instance count' do
            DeaClient.should_receive(:change_running_instances).with(app, -3)
            subject
          end
        end

        context "when the app is not started" do
          before do
            app.stub(:started?) { false }
          end

          it "should not change running instance count" do
            DeaClient.should_not_receive(:change_running_instances)
            subject
          end
        end
      end
    end
  end

  def stager_config(fog_credentials)
    {
      :resource_pool => {
        :resource_directory_key => "spec-cc-resources",
        :fog_connection => fog_credentials
      },
      :packages => {
        :app_package_directory_key => "cc-packages",
        :fog_connection => fog_credentials
      },
      :droplets => {
        :droplet_directory_key => "cc-droplets",
        :fog_connection => fog_credentials
      }
    }
  end
end
