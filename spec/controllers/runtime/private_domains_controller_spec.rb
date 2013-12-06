require "spec_helper"

module VCAP::CloudController
  describe PrivateDomainsController, type: :controller do
    describe "POST /v2/private_domains" do
      context "when owning_organization and name and wildcard are all given" do
        it "returns 201 Created" do
          org = Organization.make
          post "/v2/private_domains",
               {name: "example.com", owning_organization_guid: org.guid, wildcard: true}.to_json,
               json_headers(admin_headers)

          last_response.status.should == 201
        end

        it "creates the private domain" do
          expect {
            org = Organization.make
            post "/v2/private_domains",
                 {name: "example.com", owning_organization_guid: org.guid, wildcard: true}.to_json,
                 json_headers(admin_headers)

            response = Yajl::Parser.parse(last_response.body)
            guid = response["metadata"]["guid"]

            private_domain = PrivateDomain.find(:guid => guid)
            expect(private_domain.name).to eq("example.com")
          }.to change {
            PrivateDomain.count
          }.by(1)
        end
      end

      context "when owning_organization and wildcard is given but name is not given" do
        it "returns a 400-level error code" do
          org = Organization.make
          post "/v2/private_domains",
               {owning_organization_guid: org.guid, wildcard: true}.to_json,
               json_headers(admin_headers)

          last_response.status.should == 400
        end
      end

      context "when owning_organization and name is given but wildcard is not given" do
        it "returns a 400-level error code" do
          org = Organization.make
          post "/v2/private_domains",
               {owning_organization_guid: org.guid, name: "example.com"}.to_json,
               json_headers(admin_headers)

          last_response.status.should == 400
        end
      end

      context "when name is given but owning_organization is not given" do
        it "returns a 400-level error code" do
          post "/v2/private_domains",
               {name: "example.com", wildcard: true}.to_json,
               json_headers(admin_headers)

          last_response.status.should == 400
        end
      end

      context "when nothing is given" do
        it "returns a 400-level error code" do
          post "/v2/private_domains",
               '{}',
               json_headers(admin_headers)

          last_response.status.should == 400
        end
      end
    end

    describe "GET /v2/private_domains" do
      before do
        @private_domain_a = PrivateDomain.make
        @private_domain_b = PrivateDomain.make
      end

      it "lists all of the private domains" do
        get "/v2/private_domains", {}, admin_headers

        parsed_body = Yajl::Parser.parse(last_response.body)
        parsed_body["total_results"].should == 2
      end

      describe "GET /v2/private_domains/:guid" do
        context "when the guid is valid" do
          it "returns the correct private domain" do
            get "/v2/private_domains/#{@private_domain_a.guid}", {}, admin_headers

            last_response.status.should == 200

            parsed_body = Yajl::Parser.parse(last_response.body)
            expect(parsed_body["entity"]["name"]).to eq(@private_domain_a.name)
          end
        end

        context "when the guid is invalid" do
          it "returns a 404 error" do
            get "/v2/private_domains/some-bogus-guid", {}, admin_headers

            last_response.status.should == 404
          end
        end
      end
    end

    describe "DELETE /v2/private_domains/:guid" do
      let(:private_domain) { PrivateDomain.make }

      it "returns status code 204" do
        delete "/v2/private_domains/#{private_domain.guid}", {}, admin_headers

        last_response.status.should == 204
      end

      it "deletes the private domain" do
        expect {
          delete "/v2/private_domains/#{private_domain.guid}", {}, admin_headers
        }.to change {
          PrivateDomain.find(:guid => private_domain.guid)
        }.to(nil)
      end
    end

    describe "PUT /v2/private_domains/:guid" do
      let(:domain) { PrivateDomain.make }

      context "and a name is given" do
        it "returns 201 Created" do
          expect {
            put "/v2/private_domains/#{domain.guid}",
                '{"name":"example.com"}',
                json_headers(admin_headers)
          }.to change { domain.reload.name }.to("example.com")

          last_response.status.should == 201
        end
      end
    end
  end
end
