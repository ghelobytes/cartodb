# encoding: utf-8

require_relative '../../../spec_helper'
require_relative '../../../../app/controllers/carto/api/organizations_controller'

describe Carto::Api::OrganizationsController do
  include_context 'organization with users helper'
  include Rack::Test::Methods
  include Warden::Test::Helpers

  describe 'users unauthenticated behaviour' do

    it 'returns 401 for not logged users' do
      get api_v1_organization_users_url(id: @organization.id), @headers
      last_response.status.should == 401
    end
  end

  describe 'users' do

    before(:all) do
      @org_user_3 = create_test_user("c#{random_username}", @organization)
    end

    after(:all) do
      stub_named_maps_calls
      delete_user_data(@org_user_3)
      @org_user_3.destroy
    end

    before(:each) do
      login(@org_user_1)
    end

    # INFO: listing users though API is now needed for permission granting, for example
    it 'returns 200 for users requesting an organization that they are not owners of' do
      get api_v1_organization_users_url(id: @organization_2.id, api_key: @org_user_1.api_key), @headers
      last_response.status.should == 200
    end

    it 'returns organization users sorted by username' do
      get api_v1_organization_users_url(id: @organization.id, api_key: @org_user_1.api_key), @headers
      last_response.status.should == 200
      json_body = JSON.parse(last_response.body)
      ids = json_body['users'].map { |u| u['id'] }
      ids[0].should == @org_user_1.id
      ids[1].should == @org_user_2.id
      ids[2].should == @org_user_3.id
    end

    it 'returns organization users paged with totals' do
      page = 0
      per_page = 2
      displayed_ids = []
      total_count = @organization.users.count

      while page * per_page < total_count do
        page += 1
        get api_v1_organization_users_url(id: @organization.id, api_key: @org_user_1.api_key, page: page, per_page: per_page), @headers

        last_response.status.should == 200
        json_body = JSON.parse(last_response.body)
        ids = json_body['users'].map { |u| u['id'] }

        # Display different ids:
        (ids & displayed_ids).empty?.should == true

        expected_count = [per_page, total_count - displayed_ids.count].min
        ids.count.should == expected_count
        json_body['total_entries'].should == expected_count
        json_body['total_user_entries'].should == total_count

        displayed_ids << ids
      end

      page.should > 0
    end

    it 'returns users matching username query' do
      username = @org_user_2.username
      [username, username[1, 10], username[-4, 10]].each { |q|
        get api_v1_organization_users_url(id: @organization.id, api_key: @org_user_1.api_key, q: q), @headers
        last_response.status.should == 200
        json_body = JSON.parse(last_response.body)
        ids = json_body['users'].map { |u| u['id'] }
        ids.count.should >= 1
        ids.should include(@org_user_2.id)
      }
    end

    it 'returns users matching email query' do
      email = @org_user_2.email
      [email].each { |q|
        get api_v1_organization_users_url(id: @organization.id, api_key: @org_user_1.api_key, q: q), @headers
        last_response.status.should == 200
        json_body = JSON.parse(last_response.body)
        ids = json_body['users'].map { |u| u['id'] }
        ids.count.should == 1
        ids[0].should == @org_user_2.id
      }
    end

  end

end
