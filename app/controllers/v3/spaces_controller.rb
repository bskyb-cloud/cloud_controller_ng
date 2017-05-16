require 'presenters/v3/paginated_list_presenter'
require 'messages/spaces/spaces_list_message'
require 'messages/spaces/space_update_isolation_segment_message'
require 'actions/space_update_isolation_segment'
require 'fetchers/space_list_fetcher'

class SpacesV3Controller < ApplicationController
  def index
    message = SpacesListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      dataset: readable_spaces(message: message),
      path: '/v3/spaces',
      message: message
    )
  end

  def update_isolation_segment
    space = fetch_space(params[:guid])
    space_not_found! unless space
    org = space.organization
    org_not_found! unless org
    space_not_found! unless can_read?(space.guid, org.guid)
    unauthorized! unless roles.admin? || space.organization.managers.include?(current_user)

    message = SpaceUpdateIsolationSegmentMessage.create_from_http_request(params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    SpaceUpdateIsolationSegment.new(user_audit_info).update(space, org, message)

    isolation_segment = fetch_isolation_segment(message.isolation_segment_guid)
    render status: :ok, json: Presenters::V3::ToOneRelationshipPresenter.new(
      resource_path: "spaces/#{space.guid}",
      related_instance: isolation_segment,
      relationship_name: 'isolation_segment',
      related_resource_name: 'isolation_segments'
    )
  rescue SpaceUpdateIsolationSegment::Error => e
    unprocessable!(e.message)
  end

  def show_isolation_segment
    space = fetch_space(params[:guid])
    space_not_found! unless space

    org = space.organization
    space_not_found! unless can_read?(space.guid, org.guid)

    isolation_segment = fetch_isolation_segment(space.isolation_segment_guid)
    render status: :ok, json: Presenters::V3::ToOneRelationshipPresenter.new(
      resource_path: "spaces/#{space.guid}",
      related_instance: isolation_segment,
      relationship_name: 'isolation_segment',
      related_resource_name: 'isolation_segments'
    )
  end

  private

  def fetch_space(guid)
    Space.where(guid: guid).first
  end

  def fetch_isolation_segment(guid)
    IsolationSegmentModel.where(guid: guid).first
  end

  def space_not_found!
    resource_not_found!(:space)
  end

  def org_not_found!
    resource_not_found!(:org)
  end

  def readable_spaces(message:)
    if can_read_globally?
      SpaceListFetcher.new.fetch_all(message: message)
    else
      SpaceListFetcher.new.fetch(message: message, guids: readable_space_guids)
    end
  end
end
