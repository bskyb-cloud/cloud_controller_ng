require "spec_helper"

module VCAP::CloudController
  describe Buildpack, type: :model do
    describe "validations" do
      it "enforces unique names" do
       Buildpack.create(:name => "my_custom_buildpack", :key => "xyz", :priority => 0)

        expect {
          Buildpack.create(:name => "my_custom_buildpack", :key => "xxxx", :priority =>0)
        }.to raise_error(Sequel::ValidationFailed, /name unique/)
      end
    end

    describe "listing admin buildpacks" do
      let(:blobstore) { double :buildpack_blobstore }

      let(:buildpack_file_1) { Tempfile.new("admin buildpack 1") }
      let(:buildpack_file_2) { Tempfile.new("admin buildpack 2") }

      let(:buildpack_blobstore) { CloudController::DependencyLocator.instance.buildpack_blobstore }

      before do
        Buildpack.dataset.delete

        buildpack_blobstore.cp_to_blobstore(buildpack_file_1.path, "a key")
        @buildpack = Buildpack.make(key: "a key")

        buildpack_blobstore.cp_to_blobstore(buildpack_file_2.path, "b key")
        @another_buildpack = Buildpack.make(key: "b key")
      end

      it "returns a list of names and urls" do
        list = Buildpack.list_admin_buildpacks(CloudController::DependencyLocator.instance.blobstore_url_generator)
        expect(list).to have(2).items
        expect(list).to include(url: buildpack_blobstore.download_uri("a key"), key: "a key")
        expect(list).to include(url: buildpack_blobstore.download_uri("b key"), key: "b key")
      end

      context "when there are buildpacks with null keys" do
        before do
          Buildpack.create(:name => "nil_key_custom_buildpack", :priority => 0)
        end

        it "only returns buildpacks with non-null keys" do
          list = Buildpack.list_admin_buildpacks(CloudController::DependencyLocator.instance.blobstore_url_generator)
          expect(list).to have(2).items
          expect(list).to include(url: buildpack_blobstore.download_uri("a key"), key: "a key")
          expect(list).to include(url: buildpack_blobstore.download_uri("b key"), key: "b key")
        end
      end

      context "when there are buildpacks with empty keys" do
        before do
          Buildpack.create(:name => "nil_key_custom_buildpack", :key => "", :priority => 0)
        end

        it "only returns buildpacks with non-null keys" do
          list = Buildpack.list_admin_buildpacks(CloudController::DependencyLocator.instance.blobstore_url_generator)
          expect(list).to have(2).items
          expect(list).to include(url: buildpack_blobstore.download_uri("a key"), key: "a key")
          expect(list).to include(url: buildpack_blobstore.download_uri("b key"), key: "b key")
        end
      end
    end

    describe "staging_message" do
      it "contains the buildpack key" do
        buildpack = Buildpack.make
        expect(buildpack.staging_message).to eql(buildpack_key: buildpack.key)
      end
    end
  end
end
