require File.expand_path("../api/spec_helper", __FILE__)

describe VCAP::CloudController::Controller do
  describe "validating the auth token" do
    let(:email) { Sham.email }
    let(:user_id) { Sham.guid }
    let(:token_info) { {} }
    let(:config) {{
      :quota_definitions => [],
      :uaa => {
        :resource_id => "cloud_controller",
      },
    }}

    before do
      described_class.any_instance.stub(:config => config)
      described_class.any_instance.stub(:decode_token => token_info)
    end

    def make_request
      get "/hello/sync", {}, {"HTTP_AUTHORIZATION" => "bearer token"}
    end

    def self.it_creates_and_sets_admin_user
      it "creates admin user" do
        expect {
          make_request
        }.to change { user_count }.by(1)

        VCAP::CloudController::Models::User.order(:id).last.tap do |u|
          expect(u.guid).to eq(user_id)
          expect(u.admin).to be_true
          expect(u.active).to be_true
        end
      end

      it "sets user to created admin user" do
        make_request
        expect(VCAP::CloudController::SecurityContext.current_user).to eq(
          VCAP::CloudController::Models::User.order(:id).last
        )
      end
    end

    def self.it_sets_token_info
      it "sets token info" do
        make_request
        expect(VCAP::CloudController::SecurityContext.token).to eq token_info
      end
    end

    def self.it_does_not_create_user
      it "does not create user" do
        expect { make_request }.to_not change { user_count }
      end
    end

    def self.it_sets_found_user
      context "when user can be found" do
        before { VCAP::CloudController::Models::User.make(:guid => user_id) }

        it "sets user to found user" do
          make_request
          expect(VCAP::CloudController::SecurityContext.current_user.guid).to eq(user_id)
        end
      end

      context "when user cannot be found" do
        it "sets user to found user" do
          make_request
          expect(VCAP::CloudController::SecurityContext.current_user).to be_nil
        end
      end
    end

    def self.it_recognizes_admin_users
      context "when email is present" do
        before { token_info["email"] = email }

        context "when email matches config's bootstrap_admin email" do
          before { config[:bootstrap_admin_email] = email }

          context "when there are 0 users in the ccdb" do
            before { reset_database }
            it_creates_and_sets_admin_user
            it_sets_token_info
          end

          context "when there are >0 users" do
            before { VCAP::CloudController::Models::User.make }
            it_does_not_create_user
            it_sets_found_user
            it_sets_token_info
          end
        end

        context "when email doesn't match config bootstrap_admin email" do
          before { config[:bootstrap_admin_email] = "some-other-bootstrap-email" }

          context "when there are 0 users in the ccdb" do
            before { reset_database }
            it_does_not_create_user
            it_sets_found_user
            it_sets_token_info
          end

          context "when there are >0 users" do
            before { VCAP::CloudController::Models::User.make }
            it_does_not_create_user
            it_sets_found_user
            it_sets_token_info
          end
        end
      end

      context "when scope includes cc admin scope" do
        before { token_info["scope"] = [VCAP::CloudController::Roles::CLOUD_CONTROLLER_ADMIN_SCOPE] }
        it_creates_and_sets_admin_user
        it_sets_token_info
      end
    end

    context "when user_id is present" do
      before { token_info["user_id"] = user_id }
      it_recognizes_admin_users
    end

    context "when client_id is present" do
      before { token_info["client_id"] = user_id }
      it_recognizes_admin_users
    end

    context "when there is no user_id or client_id" do
      it_does_not_create_user

      it "sets current user to be nil because user cannot be found" do
        make_request
        expect(VCAP::CloudController::SecurityContext.current_user).to be_nil
      end

      it_sets_token_info
    end

    def user_count
      VCAP::CloudController::Models::User.count
    end
  end
end
