# Copyright (c) 2009-2012 VMware, Inc.
$:.unshift(File.expand_path("../../lib", __FILE__))

require "rubygems"
require "bundler"
require "bundler/setup"

require "machinist/sequel"
require "machinist/object"
require "rack/test"
require "timecop"

require "steno"
require "cloud_controller"
require "rspec_let_monkey_patch"
require "mock_redis"
require "webmock/rspec"

module VCAP::CloudController
  class SpecEnvironment
    def initialize
      FileUtils.mkdir_p(artifacts_dir)

      # ignore the race when we run specs in parallel
      begin
        File.unlink(log_filename)
      rescue Errno::ENOENT
      end

      Steno.init(Steno::Config.new(
        :default_log_level => "debug",
        :sinks => [Steno::Sink::IO.for_file(log_filename)]
      ))
      reset_database
    end

    def spec_dir
      File.expand_path("..", __FILE__)
    end

    def artifacts_dir
      File.join(spec_dir, "artifacts")
    end

    def artifact_filename(name)
      File.join(artifacts_dir, name)
    end

    def log_filename
      artifact_filename("spec.log")
    end

    def without_foreign_key_checks
      case db.database_type
      when :sqlite
        db.execute("PRAGMA foreign_keys = OFF")
        yield
        db.execute("PRAGMA foreign_keys = ON")
      when :mysql
        db.execute("SET foreign_key_checks = 0")
        yield
        db.execute("SET foreign_key_checks = 1")
      else
        raise "Unknown db"
      end
    end

    def reset_database
      without_foreign_key_checks do
        db.tables.each do |table|
          db.drop_table(table)
        end
        VCAP::CloudController::DB.apply_migrations(db)
      end
    end

    def db
      db_connection = "sqlite:///"
      db_index = ""

      if ENV["DB_CONNECTION"]
        db_connection = ENV["DB_CONNECTION"]
        db_index = ENV["TEST_ENV_NUMBER"]
      end

      @db ||= VCAP::CloudController::DB.connect(
        db_logger,
        :database => "#{db_connection}#{db_index}",
        :log_level => "debug2"
      )
    end

    def db_logger
      return @db_logger if @db_logger
      @db_logger = Steno.logger("cc.db")
      if ENV["DB_LOG_LEVEL"]
        level = ENV["DB_LOG_LEVEL"].downcase.to_sym
        @db_logger.level = level if Steno::Logger::LEVELS.include? level
      end
      @db_logger
    end
  end
end

$spec_env = VCAP::CloudController::SpecEnvironment.new

module VCAP::CloudController::SpecHelper
  def db
    $spec_env.db
  end

  def reset_database
    $spec_env.reset_database
    VCAP::CloudController::Models::QuotaDefinition.populate_from_config(config)
  end

  # Note that this method is mixed into each example, and so the instance
  # variable we created here gets cleared automatically after each example
  def config_override(hash)
    @config_override ||= {}
    @config_override.update(hash)

    @config = nil
    config
  end

  def config
    @config ||= begin
      config_file = File.expand_path("../../config/cloud_controller.yml", __FILE__)
      config_hash = VCAP::CloudController::Config.from_file(config_file)

      config_hash.merge!(
        :nginx => {:use_nginx => true},
        :resource_pool => {
          :resource_directory_key => "spec-cc-resources",
          :fog_connection => {
            :provider => "AWS",
            :aws_access_key_id => "fake_aws_key_id",
            :aws_secret_access_key => "fake_secret_access_key",
          }
        },
        :packages => {
          :app_package_directory_key => "cc-packages",
          :fog_connection => {
            :provider => "AWS",
            :aws_access_key_id => "fake_aws_key_id",
            :aws_secret_access_key => "fake_secret_access_key",
          }
        },
        :droplets => {
          :droplet_directory_key => "cc-droplets",
          :fog_connection => {
            :provider => "AWS",
            :aws_access_key_id => "fake_aws_key_id",
            :aws_secret_access_key => "fake_secret_access_key",
          }
        }
      )

      config_hash.merge!(@config_override || {})

      res_pool_connection_provider = config_hash[:resource_pool][:fog_connection][:provider].downcase
      packages_connection_provider = config_hash[:packages][:fog_connection][:provider].downcase
      Fog.mock! unless (res_pool_connection_provider == "local" || packages_connection_provider == "local")

      configure_components(config_hash)
      config_hash
    end
  end

  def configure_components(config)
    mbus = MockMessageBus.new(config)
    VCAP::CloudController::MessageBus.instance = mbus
    VCAP::CloudController::Models::ServiceInstance.gateway_client_class = VCAP::Services::Api::ServiceGatewayClientFake

    VCAP::CloudController::AccountCapacity.configure(config)
    VCAP::CloudController::ResourcePool.instance = VCAP::CloudController::ResourcePool.new(config)
    VCAP::CloudController::AppPackage.configure(config)
    VCAP::CloudController::AppStager.configure(config, mbus)
    VCAP::CloudController::LegacyStaging.configure(config)

    VCAP::CloudController::DeaPool.configure(config, mbus)
    VCAP::CloudController::DeaClient.configure(config, mbus)
    VCAP::CloudController::HealthManagerClient.configure(mbus)

    VCAP::CloudController::LegacyBulk.configure(config, mbus)
    VCAP::CloudController::Models::QuotaDefinition.configure(config)
  end

  def configure
    config
  end

  def create_zip(zip_name, file_count, file_size=1024)
    total_size = file_count * file_size
    files = []
    file_count.times do |i|
      tf = Tempfile.new("ziptest_#{i}")
      files << tf
      tf.write("A" * file_size)
      tf.close
    end
    child = POSIX::Spawn::Child.new("zip", zip_name, *files.map(&:path))
    child.status.exitstatus.should == 0
    total_size
  end

  def with_em_and_thread(opts = {}, &blk)
    auto_stop = opts.has_key?(:auto_stop) ? opts[:auto_stop] : true
    Thread.abort_on_exception = true

    # Make sure that thread pool for defers is 1
    # so that it acts as a simple run loop.
    EM.threadpool_size = 1

    EM.run do
      Thread.new do
        blk.call
        stop_em_when_all_defers_are_done if auto_stop
      end
    end
  end

  def stop_em_when_all_defers_are_done
    stop_em = lambda {
      # Account for defers/timers made from within defers/timers
      if EM.defers_finished? && em_timers_finished?
        EM.stop
      else
        # Note: If we put &stop_em in a oneshot timer
        # calling EM.stop does not stop EM; however,
        # calling EM.stop in the next tick does.
        # So let's just do next_tick...
        EM.next_tick(&stop_em)
      end
    }
    EM.next_tick(&stop_em)
  end

  def em_timers_finished?
    all_timers = EM.instance_variable_get("@timers")
    active_timers = all_timers.select { |tid, t| t.respond_to?(:call) }
    active_timers.empty?
  end

  def em_inspect_timers
    puts EM.instance_variable_get("@timers").inspect
  end

  RSpec::Matchers.define :be_recent do |expected|
    match do |actual|
      actual.should be_within(5).of(Time.now)
    end
  end

  # @param [Hash] expecteds key-value pairs of messages and responses
  # @return [#==]
  RSpec::Matchers.define(:respond_with) do |expecteds|
    match do |actual|
      expecteds.all? do |message, matcher|
        if matcher.respond_to?(:matches?)
          matcher.matches?(actual.public_send(message))
        else
          matcher == actual.public_send(message)
        end
      end
    end
  end

  RSpec::Matchers.define :json_match do |matcher|
    # RSpect matcher?
    if matcher.respond_to?(:matches?)
      match do |json|
        actual = Yajl::Parser.parse(json)
        matcher.matches?(actual)
      end
      # regular values or RSpec Mocks argument matchers
    else
      match do |json|
        actual = Yajl::Parser.parse(json)
        matcher == actual
      end
    end
  end

  shared_examples "a vcap rest error response" do |description_match|
    let(:decoded_response) { Yajl::Parser.parse(last_response.body) }

    it "should contain a numeric code" do
      decoded_response["code"].should_not be_nil
      decoded_response["code"].should be_a_kind_of(Fixnum)
    end

    it "should contain a description" do
      decoded_response["description"].should_not be_nil
      decoded_response["description"].should be_a_kind_of(String)
    end

    if description_match
      it "should contain a description that matches #{description_match}" do
        decoded_response["description"].should match(/#{description_match}/)
      end
    end
  end

  shared_context "resource pool" do
    before(:all) do
      num_dirs = 3
      num_unique_allowed_files_per_dir = 7
      file_duplication_factor = 2
      @max_file_size = 1098 # this is arbitrary

      @total_allowed_files =
        num_dirs * num_unique_allowed_files_per_dir * file_duplication_factor

      @dummy_descriptor = {"sha1" => Digest::SHA1.hexdigest("abc"), "size" => 1}
      @tmpdir = Dir.mktmpdir

      @descriptors = []
      num_dirs.times do
        dirname = SecureRandom.uuid
        Dir.mkdir("#{@tmpdir}/#{dirname}")
        num_unique_allowed_files_per_dir.times do
          basename = SecureRandom.uuid
          path = "#{@tmpdir}/#{dirname}/#{basename}"
          contents = SecureRandom.uuid

          descriptor = {
            "sha1" => Digest::SHA1.hexdigest(contents),
            "size" => contents.length
          }
          @descriptors << descriptor

          file_duplication_factor.times do |i|
            File.open("#{path}-#{i}", "w") do |f|
              f.write contents
            end
          end

          File.open("#{path}-not-allowed", "w") do |f|
            f.write "A" * @max_file_size
          end
        end
      end
    end

    before(:all) do
      Fog.mock!

      @resource_pool = VCAP::CloudController::ResourcePool.new(
        :resource_pool => {
          :maximum_size => @max_file_size,
          :resource_directory_key => "spec-cc-resources",
          :fog_connection => {
            :provider => "AWS",
            :aws_access_key_id => "fake_aws_key_id",
            :aws_secret_access_key => "fake_secret_access_key",
          }
        }
      )
    end

    after(:all) do
      FileUtils.rm_rf(@tmpdir)
    end
  end
end

class CF::UAA::Misc
  def self.validation_key(*args)
    raise CF::UAA::TargetError.new('error' => 'unauthorized')
  end
end

class Redis
  def self.new(*args)
    MockRedis.new
  end
end

RSpec.configure do |rspec_config|
  rspec_config.include VCAP::CloudController
  rspec_config.include Rack::Test::Methods
  rspec_config.include VCAP::CloudController::SpecHelper

  rspec_config.before(:all) do
    VCAP::CloudController::SecurityContext.clear
    configure
  end
end

require "cloud_controller/models"
Dir.glob(File.join(File.dirname(__FILE__), "support/**/*.rb")).each { |f| require f }

require "models/spec_helper"
