require 'jobs/cc_job'
require 'jobs/runtime/pending_droplet_cleanup'
require 'jobs/runtime/app_events_cleanup'
require 'jobs/runtime/app_usage_events_cleanup'
require 'jobs/runtime/blobstore_delete'
require 'jobs/runtime/blobstore_upload'
require 'jobs/runtime/buildpack_cache_cleanup'
require 'jobs/runtime/buildpack_delete'
require 'jobs/runtime/buildpack_installer'
require 'jobs/runtime/events_cleanup'
require 'jobs/runtime/model_deletion'
require 'jobs/runtime/legacy_jobs'
require 'jobs/runtime/failed_jobs_cleanup'
require 'jobs/runtime/prune_completed_tasks'
require 'jobs/runtime/delete_expired_droplet_blob'
require 'jobs/runtime/delete_expired_package_blob'
require 'jobs/runtime/expired_blob_cleanup'
require 'jobs/runtime/expired_resource_cleanup'
require 'jobs/services/service_usage_events_cleanup'
require 'jobs/v3/droplet_bits_copier'
require 'jobs/v3/package_bits'
require 'jobs/v3/package_bits_copier'
require 'jobs/v3/droplet_upload'
require 'jobs/v3/buildpack_cache_upload'
require 'jobs/v2/upload_droplet_from_user'
require 'jobs/enqueuer'
require 'jobs/wrapping_job'
require 'jobs/exception_catching_job'
require 'jobs/request_job'
require 'jobs/timeout_job'
require 'jobs/local_queue'
require 'jobs/delete_action_job'
require 'jobs/services/legacy_jobs/service_instance_deletion'
require 'jobs/diego/sync'
