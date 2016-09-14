require 'spec_helper'

module VCAP::CloudController
  RSpec.describe SshController, type: :v2_controller do
    describe 'GET /v2/apps/:id/instances/ssh' do
      before :each do
        @app = AppFactory.make(package_hash: 'abc', package_state: 'STAGED')
        @user = make_user_for_space(@app.space)
        @developer = make_developer_for_space(@app.space)
        @auditor = make_auditor_for_space(@app.space)
      end

      context 'as a developer' do
        before :each do
          set_current_user(@developer)
        end

        it 'should return 400 when there is an error finding the instances' do
          instance_id = 5

          @app.state = 'STARTED'
          @app.save

          get "/v2/apps/#{@app.guid}/instances/#{instance_id}/ssh"

          expect(last_response.status).to eq 400
        end

        it 'should return the ssh details' do
          @app.state = 'STARTED'
          @app.instances = 1
          @app.save

          @app.refresh

          response = {
            'ip' => VCAP.local_ip,
            'sshkey' => 'fakekey',
            'user' => 'vcap',
            'port' => 1234
          }

          expected = {
            'ip' => VCAP.local_ip,
            'sshkey' => 'fakekey',
            'user' => 'vcap',
            'port' => 1234
          }

          Dea::Client.should_receive(:ssh_instance).with(@app, 0).
            and_return(response)

          get "v2/apps/#{@app.guid}/instances/0/ssh"

          expect(last_response.status).to eq 200
          expect(Yajl::Parser.parse(last_response.body)).to eq expected
        end
      end

      context 'as a user' do
        it 'should return 403' do
          set_current_user(@user)

          get "v2/apps/#{@app.guid}/instances/0/ssh"

          expect(last_response.status).to eq 403
        end
      end

      context 'as a auditor' do
        it 'should return the ssh details' do
          @app.state = 'STARTED'
          @app.instances = 1
          @app.save

          @app.refresh

          response = {
            'ip' => VCAP.local_ip,
            'sshkey' => 'fakekey',
            'user' => 'vcap',
            'port' => 1234
          }

          expected = {
            'ip' => VCAP.local_ip,
            'sshkey' => 'fakekey',
            'user' => 'vcap',
            'port' => 1234
          }

          Dea::Client.should_receive(:ssh_instance).with(@app, 0).
            and_return(response)

          set_current_user(@auditor)

          get "v2/apps/#{@app.guid}/instances/0/ssh"

          expect(last_response.status).to eq 200
          expect(Yajl::Parser.parse(last_response.body)).to eq expected
        end
      end
    end
  end
end
