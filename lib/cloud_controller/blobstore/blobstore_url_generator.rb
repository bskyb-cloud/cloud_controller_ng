module CloudController
  class BlobstoreUrlGenerator
    def initialize(blobstore_options, package_blobstore, buildpack_cache_blobstore, admin_buildpack_blobstore)
      @blobstore_options = blobstore_options
      @package_blobstore = package_blobstore
      @buildpack_cache_blobstore = buildpack_cache_blobstore
      @admin_buildpack_blobstore = admin_buildpack_blobstore
    end

    # Downloads
    def app_package_download_url(app)
      generate_download_url(@package_blobstore, "/staging/apps/#{app.guid}", app.guid)
    end

    def buildpack_cache_download_url(app)
      generate_download_url(@buildpack_cache_blobstore, "/staging/buildpack_cache/#{app.guid}/download", app.guid)
    end

    def admin_buildpack_download_url(buildpack)
      if @admin_buildpack_blobstore.local?
        staging_uri("/buildpacks/#{buildpack.guid}/download")
      else
        @admin_buildpack_blobstore.download_uri(buildpack.key)
      end
    end

    # Uploads
    def droplet_upload_url(app)
      staging_uri("/staging/droplets/#{app.guid}/upload")
    end

    def buildpack_cache_upload_url(app)
      staging_uri("/staging/buildpack_cache/#{app.guid}/upload")
    end

    private
    def generate_download_url(store, path, blobstore_key)
      if store.local?
        staging_uri(path)
      else
        store.download_uri(blobstore_key)
      end
    end

    def staging_uri(path)
      URI::HTTP.build(
        host: @blobstore_options[:blobstore_host],
        port: @blobstore_options[:blobstore_port],
        userinfo: [@blobstore_options[:user], @blobstore_options[:password]],
        path: path,
      ).to_s
    end
  end
end
