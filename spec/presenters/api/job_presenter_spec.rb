require 'spec_helper'

describe JobPresenter do
  describe "#to_hash" do
    let(:job) do
      job = Delayed::Job.enqueue double(:obj, perform: nil)
      job.stub(:run_at) { Time.now.months_since(1) }
      job
    end

    it "creates a valid JSON" do
      expect(JobPresenter.new(job).to_hash).to eq(
        metadata: {
          guid: job.guid,
          created_at: job.created_at.iso8601,
          url: "/v2/jobs/#{job.guid}"
        },
        entity: {
          guid: job.guid,
          status: "queued"
        }
      )
    end

    it "creates full url if required" do
      url_host_name = "http://example.com"
      expect(JobPresenter.new(job, url_host_name).to_hash.fetch(:metadata).fetch(:url)).to eq("#{url_host_name}/v2/jobs/#{job.guid}")
    end

    context "when the job has started" do
      let(:job) do
        job = Delayed::Job.enqueue double(:obj, perform: nil)
        job.stub(:locked_at) { Time.now }
        job
      end

      it "creates a valid JSON" do
        expect(JobPresenter.new(job).to_hash).to eq(
          metadata: {
            guid: job.guid,
            created_at: job.created_at.iso8601,
            url: "/v2/jobs/#{job.guid}"
          },
          entity: {
            guid: job.guid,
            status: "running"
          }
        )
      end
    end

    context "when the job does not exist (i.e. it finished and was deleted)" do
      let(:job) { nil }

      it "creates a valid JSON" do
        expect(JobPresenter.new(job).to_hash).to eq(
          metadata: {
            guid: "0",
            created_at: Time.at(0).iso8601,
            url: "/v2/jobs/0"
          },
          entity: {
            guid: "0",
            status: "finished"
          }
        )
      end
    end

    context "when the job has an error" do
      let(:exception) { VCAP::Errors::BuildpackLocked.new }
      let(:job) { Delayed::Job.enqueue double(:obj, perform: nil) }
      before do
        allow(job).to receive(:cf_api_error).and_return(VCAP::CloudController::ExceptionMarshaler.marshal(exception))
      end

      it "creates a valid JSON" do
        expect(JobPresenter.new(job).to_hash).to eq(
          metadata: {
            guid: job.guid,
            created_at: job.created_at.iso8601,
            url: "/v2/jobs/#{job.guid}"
          },
          entity: {
            guid: job.guid,
            status: "failed",
            error: "Use of entity>error is deprecated in favor of entity>error_details.",
            error_details: ErrorPresenter.new(exception).sanitized_hash
          }
        )
      end
    end

    context "when the job has an error" do
      let(:exception) { VCAP::Errors::BuildpackLocked.new }
      let(:job) { Delayed::Job.enqueue double(:obj, perform: nil) }
      before do
        allow(job).to receive(:cf_api_error).and_return(nil)
        allow(job).to receive(:last_error).and_return("backtrace")
      end

      it "creates a valid JSON" do
        expect(JobPresenter.new(job).to_hash).to eq(
           metadata: {
             guid: job.guid,
             created_at: job.created_at.iso8601,
             url: "/v2/jobs/#{job.guid}"
           },
           entity: {
             guid: job.guid,
             status: "failed",
             error: "Use of entity>error is deprecated in favor of entity>error_details.",
             error_details: {
               "error_code" => "UnknownError",
               "description" => "An unknown error occurred.",
               "code" => 10001,
             }
           }
         )
      end
    end
  end
end
