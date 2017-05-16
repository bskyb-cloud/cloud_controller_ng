$LOAD_PATH.unshift(File.expand_path('../models', __FILE__))

require 'diego/bbs/models/actions.pb'
require 'diego/bbs/models/actual_lrp.pb'
require 'diego/bbs/models/actual_lrp_requests.pb'
require 'diego/bbs/models/cached_dependency.pb'
require 'diego/bbs/models/cells.pb'
require 'diego/bbs/models/desired_lrp.pb'
require 'diego/bbs/models/desired_lrp_requests.pb'
require 'diego/bbs/models/domain.pb'
require 'diego/bbs/models/environment_variables.pb'
require 'diego/bbs/models/error.pb'
require 'diego/bbs/models/evacuation.pb'
require 'diego/bbs/models/events.pb'
require 'diego/bbs/models/lrp_convergence_request.pb'
require 'diego/bbs/models/modification_tag.pb'
require 'diego/bbs/models/network.pb'
require 'diego/bbs/models/ping.pb'
require 'diego/bbs/models/security_group.pb'
require 'diego/bbs/models/task.pb'
require 'diego/bbs/models/task_requests.pb'
require 'diego/bbs/models/volume_mount.pb'
