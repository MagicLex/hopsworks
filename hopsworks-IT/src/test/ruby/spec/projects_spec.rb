# coding: utf-8
=begin
 Changes to this file committed after and not including commit-id: ccc0d2c5f9a5ac661e60e6eaf138de7889928b8b
 are released under the following license:

 This file is part of Hopsworks
 Copyright (C) 2018, Logical Clocks AB. All rights reserved

 Hopsworks is free software: you can redistribute it and/or modify it under the terms of
 the GNU Affero General Public License as published by the Free Software Foundation,
 either version 3 of the License, or (at your option) any later version.

 Hopsworks is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 PURPOSE.  See the GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License along with this program.
 If not, see <https://www.gnu.org/licenses/>.

 Changes to this file committed before and including commit-id: ccc0d2c5f9a5ac661e60e6eaf138de7889928b8b
 are released under the following license:

 Copyright (C) 2013 - 2018, Logical Clocks AB and RISE SICS AB. All rights reserved

 Permission is hereby granted, free of charge, to any person obtaining a copy of this
 software and associated documentation files (the "Software"), to deal in the Software
 without restriction, including without limitation the rights to use, copy, modify, merge,
 publish, distribute, sublicense, and/or sell copies of the Software, and to permit
 persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or
 substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS  OR IMPLIED, INCLUDING
 BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 DAMAGES OR  OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
=end

describe "On #{ENV['OS']}" do
  after(:all) {clean_all_test_projects(spec: "project")}
  describe 'projects' do
    describe "#create" do
      context 'without authentication' do
        before :all do
          reset_session
        end
        it "should fail" do
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: "project_#{Time.now.to_i}", description: "", status: 0, services: ["JOBS","HIVE"], projectTeam:[], retentionPeriod: ""}
          expect_status_details(401, error_code: 200003)
        end
      end

      context 'with authentication' do
        before :all do
          with_valid_session
        end
        before :each do
          check_project_limit
        end
        it 'should work with valid params' do
          projectname = "project_#{Time.now.to_i}"
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: "#{projectname}", description: "", status: 0, services: ["JOBS","HIVE"], projectTeam:[], retentionPeriod: ""}
          expect_json(successMessage: regex("Project created successfully.*"))
          expect_status_details(201)
          get "#{ENV['HOPSWORKS_API']}/project/getProjectInfo/#{projectname}"
          project_id = json_body[:projectId]
          get "#{ENV['HOPSWORKS_API']}/project/#{project_id}"
          expect_status_details(200)
        end
        it 'should create resources and logs datasets with right permissions and owner' do
          projectname = "project_#{Time.now.to_i}"
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: projectname, description: "", status: 0, services: ["JOBS","HIVE"], projectTeam:[], retentionPeriod: ""}
          expect_json(successMessage: regex("Project created successfully.*"))
          expect_status_details(201)
          get "#{ENV['HOPSWORKS_API']}/project/getProjectInfo/#{projectname}"
          project_id = json_body[:projectId]
          get "#{ENV['HOPSWORKS_API']}/project/#{project_id}/dataset/?action=listing&expand=inodes"
          expect_status_details(200)
          logs = json_body[:items].detect { |e| e[:name] == "Logs" }
          resources = json_body[:items].detect { |e| e[:name] == "Resources" }
          expect(logs[:description]).to eq ("Contains the logs for jobs that have been run through the Hopsworks platform.")
          expect(logs[:attributes][:permission]).to eq ("rwxrwx---")
          expect(logs[:attributes][:owner]).to eq ("#{@user[:fname]} #{@user[:lname]}")
          expect(resources[:description]).to eq ("Contains resources used by jobs, for example, jar files.")
          expect(resources[:attributes][:permission]).to eq ("rwxrwx---")
          expect(resources[:attributes][:owner]).to eq ("#{@user[:fname]} #{@user[:lname]}")
        end

        it 'should create JUPYTER dataset with right permissions and owner' do
          projectname = "project_#{Time.now.to_i}"
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: projectname, description: "", status: 0, services: ["JOBS","HIVE", "JUPYTER"], projectTeam:[], retentionPeriod: ""}
          expect_json(successMessage: regex("Project created successfully.*"))
          expect_status_details(201)
          get "#{ENV['HOPSWORKS_API']}/project/getProjectInfo/#{projectname}"
          project_id = json_body[:projectId]
          get "#{ENV['HOPSWORKS_API']}/project/#{project_id}/dataset/?action=listing&expand=inodes"
          expect_status_details(200)
          notebook = json_body[:items].detect { |e| e[:name] == "Jupyter" }
          expect(notebook[:description]).to eq("Contains Jupyter notebooks.")
          expect(notebook[:attributes][:permission]).to eq("rwxrwx---")
          expect(notebook[:attributes][:owner]).to eq("#{@user[:fname]} #{@user[:lname]}")
        end

        it 'should fail to create a project with an existing name' do
          with_valid_project
          projectname = "#{@project[:projectname]}"
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: projectname, description: "", status: 0, services: ["JOBS","HIVE"], projectTeam:[], retentionPeriod: ""}
          expect_status_details(409, error_code: 150001)
        end

        it 'Should fail to create two projects with the same name but different capitalization - HOPSWORKS-256' do
          check_project_limit(2)
          projectName = "HOPSWORKS256#{short_random_id}"
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: projectName, description: "", status: 0, services: [], projectTeam:[], retentionPeriod: ""}
          expect_status_details(201)
          expect_json(successMessage: regex("Project created successfully.*"))

          post "#{ENV['HOPSWORKS_API']}/project", {projectName: projectName.downcase, description: "", status: 0, services: [], projectTeam:[], retentionPeriod: ""}
          expect_status_details(409, error_code: 150001)
        end

        it 'Should fail to create two projects with the same name but different capitalization - HOPSWORKS-256' do
          check_project_limit(2)
          projectName = "hopsworks256#{short_random_id}"
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: projectName, description: "", status: 0, services: [], projectTeam:[], retentionPeriod: ""}
          expect_status_details(201)
          expect_json(successMessage: regex("Project created successfully.*"))

          post "#{ENV['HOPSWORKS_API']}/project", {projectName: projectName.upcase, description: "", status: 0, services: [], projectTeam:[], retentionPeriod: ""}
          expect_status_details(409, error_code: 150001)
        end

        it 'should create a project X containing a dataset Y after deleting a project X containing a dataset Y (issue #425)' do
          check_project_limit(2)
          projectname = "project_#{short_random_id}"
          project = create_project_by_name(projectname)
          dsname = "dataset_#{short_random_id}"
          create_dataset_by_name_checked(project, dsname, permission: "READ_ONLY")
          delete_project(project)

          sleep(15)

          project = create_project_by_name(projectname)
          create_dataset_by_name_checked(project, dsname, permission: "READ_ONLY")

          get "#{ENV['HOPSWORKS_API']}/project/#{project[:id]}/dataset/#{dsname}?action=listing&expand=inodes"
          expect_status_details(200)
          get "#{ENV['HOPSWORKS_API']}/project/#{project[:id]}/dataset/?action=listing&expand=inodes"
          ds = json_body[:items].detect { |d| d[:name] == dsname }
          expect(ds[:attributes][:owner]).to eq ("#{@user[:fname]} #{@user[:lname]}")
        end

        it 'should create a project given only name' do
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: "project_#{Time.now.to_i}"}
          expect_status_details(201)
        end

        it 'Should not let a user create more than the maximum number of allowed projects.' do
          create_max_num_projects
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: "project_#{Time.now.to_i}"}
          expect_status_details(400, error_code: 150002)
        end

        it 'Should fail to create projects with invalid chars - .' do
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: "project_."}
          expect_status_details(400, error_code: 150003)
        end

        it 'Should fail to create projects with invalid chars - __' do
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: "project__fail"}
          expect_status_details(400, error_code: 150003)
        end

        it 'Should fail to create projects with invalid chars - Ö' do
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: "projectÖfail"}
          expect_status_details(400, error_code: 150003)
        end

        it 'Should fail to create a project with a name starting with _' do
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: "_projectfail"}
          expect_status_details(400, error_code: 150003)
        end
      end

      context "project creation failure" do
        before :all do
          @failed_service = "kibana"
          @service_host = ENV['KIBANA_API'].split(":").map(&:strip)[0]
          with_valid_session
        end
        
        after :all do
          # Make sure we bring back the service
          execute_remotely @service_host, "sudo systemctl start #{@failed_service}"
          sleep 60
        end
        
        it "Should be able to create a Project after a failed attempt" do
          # First shutdown the service
          execute_remotely @service_host, "sudo systemctl stop #{@failed_service}"
          project_name = "ProJect_doomed2fail#{random_id_len(2)}"
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: project_name,
                                                  services: ["JOBS","JUPYTER"]}
          expect_status_details(500)
          # Now bring back service and try again
          execute_remotely @service_host, "sudo systemctl start #{@failed_service}"
          # Give it some time to become ready
          sleep 60
          post "#{ENV['HOPSWORKS_API']}/project", {projectName: project_name,
                                                   services: ["JOBS","JUPYTER"]}
          expect_status_details(201)
        end
      end
    end
    
    describe "#access" do
      context 'without authentication' do
        before :all do
          reset_session
        end
        it "should fail to get project list" do
          get "#{ENV['HOPSWORKS_API']}/project/getAll"
          expect_status_details(401, error_code: 200003)
        end
      end
      context 'with authentication' do
        before :all do
          with_valid_session
        end
        it "should return project list" do
          get "#{ENV['HOPSWORKS_API']}/project/getAll"
          expect_json_types :array
          expect_status_details(200)
        end
      end

      context 'with authentication and project' do
        before :all do
          with_valid_project
        end

        it "should be able to download trust and keystore as well as pem format credentials" do
          project_id = get_project.id
          download_cert_endpoint = "#{ENV['HOPSWORKS_API']}/project/" + project_id.to_s + "/downloadCert"
          data = 'password=Pass123'
          headers = {"Content-Type" => 'application/x-www-form-urlencoded'}
          json_result = post download_cert_endpoint, data, headers
          parsed_json = JSON.parse(json_result)
          expect_status_details(200)
          expect(parsed_json["fileExtension"]).to eql("jks")
          expect(parsed_json.key?("kStore")).to be true
          expect(parsed_json.key?("tStore")).to be true
          expect(parsed_json.key?("password")).to be true
          expect(parsed_json.key?("caChain")).to be true
          expect(parsed_json.key?("clientCert")).to be true
          expect(parsed_json.key?("clientKey")).to be true
        end
      end
    end
    describe "#delete" do
      context 'without authentication' do
        before :all do
          with_valid_project
          reset_session
        end
        it "should fail to delete project" do
          project = get_project
          post "#{ENV['HOPSWORKS_API']}/project/#{project[:id]}/delete"
          expect_status_details(401, error_code: 200003)
        end
      end
      context 'with authentication but insufficient privilege' do
        before :all do
          with_valid_project
          reset_session
        end
        it "should fail to delete project with insufficient privilege" do
          member = create_user
          add_member(member[:email], "Data scientist")
          project = get_project
          create_session(member[:email],"Pass123")
          post "#{ENV['HOPSWORKS_API']}/project/#{project[:id]}/delete"
          expect_status_details(403, error_code: 150068)
        end

        it "should succeed if user is Hopsworks administrator" do
          project = get_project
          with_admin_session
          delete "#{ENV['HOPSWORKS_API']}/admin/projects/#{project[:id]}"
          expect_status_details(200)
          expect_json(successMessage: "The project and all related files were removed successfully.")
        end
      end
      
      context 'with authentication and sufficient privilege' do
        before :all do
          with_valid_project
        end
        before :each do
          check_project_limit(1)
        end
        it "should delete project" do
          # Start Jupyter to put X.509 to HDFS
          @project = create_env_and_update_project(@project, ENV['PYTHON_VERSION'])
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/jupyter/settings"
          expect_status_details(200)
          settings = json_body
          settings[:distributionStrategy] = ""
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/jupyter/start", JSON(settings)
          expect_status_details(200)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/jupyter/running"
          expect_status_details(200)

          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/delete"
          expect_status_details(200)
          expect_json(successMessage: "The project and all related files were removed successfully.")

          # Deleting a project even with Jupyter running should leave no references behind
          user = User.find_by(email: @project[:username])
          project_username = @project[:projectname] + "__" + user.username
          expect(RemoteMaterialReferences.find_by(username: @project[:projectname])).to be_nil
        end
        it "should delete and recreate spark tour" do
          project = create_project_tour("spark")
          delete_project(project)
          sleep(15)
          project = create_project_tour("spark")
          delete_project(project)
        end
        it "should delete and recreate kafka tour" do
          project = create_project_tour("kafka")
          delete_project(project)
          sleep(15)
          project = create_project_tour("kafka")
          delete_project(project)
        end
        it "should delete and recreate deep_learning tour" do
          project = create_project_tour("ml")
          delete_project(project)
          sleep(15)
          project = create_project_tour("ml")
          delete_project(project)
        end
        it "should delete and recreate featurestore tour" do
          project = create_project_tour("fs")
          job_name = "featurestore_tour_job"
          wait_result = wait_for_me_time do
            get_executions(project[:id], job_name)
            execution_id = json_body[:items][0][:id]
            stop_execution(project[:id], job_name, execution_id)
            get_execution(project[:id], job_name, execution_id)
            { 'success' => (json_body[:state].eql? "KILLED"), 'msg' => "expected:KILLED, found:#{json_body[:state]}" }
          end
          expect(wait_result["success"]).to be(true), wait_result["msg"]
          delete_project(project)
          sleep(15)
          project = create_project_tour("fs")
          wait_result = wait_for_me_time do
            get_executions(project[:id], job_name)
            execution_id = json_body[:items][0][:id]
            stop_execution(project[:id], job_name, execution_id)
            get_execution(project[:id], job_name, execution_id)
            { 'success' => (json_body[:state].eql? "KILLED"), 'msg' => "expected:KILLED, found:#{json_body[:state]}" }
          end
          expect(wait_result["success"]).to be(true), wait_result["msg"]
          delete_project(project)
        end
      end
    end
    describe "#update" do
      context 'without authentication' do
        before :all do
          with_valid_project
          reset_session
        end
        it "should fail to add member" do
          project = get_project
          member = create_user[:email]
          post "#{ENV['HOPSWORKS_API']}/project/#{project[:id]}/projectMembers", {projectTeam: [{projectTeamPK: {projectId: project[:id], teamMember: member},teamRole: "Data scientist"}]}
          expect_status_details(401, error_code: 200003)
        end
      end
      context 'with authentication but insufficient privilege' do
        before :all do
          with_valid_project
          reset_session
        end
        it "should fail to add member" do
          member = create_user
          new_member = create_user[:email]
          add_member(member[:email], "Data scientist")
          project = get_project
          create_session(member[:email],"Pass123")
          post "#{ENV['HOPSWORKS_API']}/project/#{project[:id]}/projectMembers", {projectTeam: [{projectTeamPK: {projectId: project[:id], teamMember: new_member},teamRole: "Data scientist"}]}
          expect_status_details(403, error_code: 150068)
        end
        it "should fail to remove a team member" do
          member = create_user
          new_member = create_user[:email]
          add_member(member[:email], "Data scientist")
          add_member(new_member, "Data scientist")
          project = get_project
          create_session(member[:email],"Pass123")
          delete "#{ENV['HOPSWORKS_API']}/project/#{project[:id]}/projectMembers/#{new_member}"
          expect_status_details(403, error_code: 150012)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == new_member }
          expect(memb).to be_present
        end
        it "should fail to change member role" do
          member = create_user
          new_member = create_user[:email]
          add_member(member[:email], "Data scientist")
          add_member(new_member, "Data owner")
          project = get_project
          create_session(member[:email],"Pass123")
          post "#{ENV['HOPSWORKS_API']}/project/#{project[:id]}/projectMembers/#{new_member}", URI.encode_www_form({ role: "Data scientist"}), { content_type: 'application/x-www-form-urlencoded'}
          expect_status_details(403, error_code: 150068)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == new_member }
          expect(memb[:teamRole]).to eq("Data owner")
        end
      end
      context 'with authentication and sufficient privilege' do
        before :all do
          with_valid_project
        end
        it "should add new member" do
          new_member = create_user[:email]
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers", {projectTeam: [{projectTeamPK: {projectId: @project[:id],teamMember: new_member},teamRole: "Data scientist"}]}
          expect_json(successMessage: "One member added successfully")
          expect_status_details(200)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == new_member }
          expect(memb[:teamRole]).to eq ("Data scientist")
        end
        it "should add new member to kube config map" do
          if !kserve_installed
            skip "This test only runs with KServe installed"
          end
          new_member = create_user
          email = new_member[:email]
          username = new_member[:username]
          add_member(email, "Data scientist")
          cm = get_project_teams_kube_config_map(@project[:projectname])
          expect(cm).not_to be_empty
          expect(cm).to include("data")
          expect(cm["data"]).to include(username)
          expect(cm["data"][username]).to eql "Data scientist"
        end
        it "should copy kube serving secret when adding a new member" do
          if !kserve_installed
            skip "This test only runs with KServe installed"
          end
          new_member = create_user
          email = new_member[:email]
          username = new_member[:username]
          add_member(email, "Data scientist")
          secret = get_api_key_kube_project_serving_secret(@project[:projectname], username)
          expect(secret).not_to be_nil
          expect(secret).to include("data")
          expect(secret["data"]).to include("apiKey")
        end
        it "should remove data owner from project when remove issued by another data owner" do
          new_member = create_user[:email]
          add_member(new_member, "Data owner")
          delete "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{new_member}"
          expect_status_details(200)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == new_member }
          expect(memb).to be_nil
        end
        it "should remove old member from kube config map" do
          if !kserve_installed
            skip "This test only runs with KServe installed"
          end
          new_member = create_user
          email = new_member[:email]
          username = new_member[:username]
          add_member(email, "Data owner")
          cm = get_project_teams_kube_config_map(@project[:projectname])
          expect(cm).not_to be_empty
          expect(cm).to include("data")
          expect(cm["data"]).to include(username)
          expect(cm["data"][username]).to eql "Data owner"
          remove_member(@project, email)
          cm = get_project_teams_kube_config_map(@project[:projectname])
          expect(cm).not_to be_empty
          expect(cm).to include("data")
          expect(cm["data"]).not_to include(username)
        end
        it "should delete kube serving secret when removing a new member" do
          if !kserve_installed
            skip "This test only runs with KServe installed"
          end
          new_member = create_user
          email = new_member[:email]
          username = new_member[:username]
          add_member(email, "Data owner")
          secret = get_api_key_kube_project_serving_secret(@project[:projectname], username)
          expect(secret).not_to be_nil
          remove_member(@project, email)
          secret = get_api_key_kube_project_serving_secret(@project[:projectname], username)
          expect(secret).to be_nil
        end
        it "should remove data scientist from project when remove issued by data owner" do
          new_member = create_user[:email]
          add_member(new_member, "Data scientist")
          delete "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{new_member}"
          expect_status_details(200)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == new_member }
          expect(memb).to be_nil
        end
        it "should fail for project owner to remove themselves from project" do
          delete "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{@user[:email]}"
          expect_status_details(403, error_code: 150013)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == @user[:email] }
          expect(memb).should_not be_nil
        end
        it "should fail for data scientist to remove data owner from project" do
          data_owner = @user[:email]
          new_member = create_user[:email]
          add_member(new_member, "Data scientist")
          reset_session
          create_session(new_member,"Pass123")
          delete "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{data_owner}"
          expect_status_details(403, error_code: 150012)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == data_owner }
          expect(memb).should_not be_nil
          reset_session
          create_session(data_owner,"Pass123")
        end
        it "should fail to remove a non-existing team member" do
          new_member = create_user[:email]
          delete "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{new_member}"
          expect_status_details(404, error_code: 150023)
        end
        it "should add new member with default role (Data scientist)" do
          new_member = create_user[:email]
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers", {projectTeam: [{projectTeamPK: {projectId: @project[:id],teamMember: new_member},teamRole: ""}]}
          expect_json(successMessage: "One member added successfully")
          expect_status_details(200)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == new_member }
          expect(memb[:teamRole]).to eq ("Data scientist")
        end
        it "should fail to change non-existing user role" do
          new_member = "none_existing_user@email.com"
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{new_member}", URI.encode_www_form({ role: "Data scientist"}), { content_type: 'application/x-www-form-urlencoded'}
          expect_status_details(404, error_code: 160002)
        end
        it "should fail to change non-existing member role" do
          new_member = create_user[:email]
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{new_member}", URI.encode_www_form({ role: "Data scientist"}), { content_type: 'application/x-www-form-urlencoded'}
          expect_status_details(404, error_code: 150023)
        end
        it "should change member role to Data scientist" do
          new_member = create_user[:email]
          add_member(new_member, "Data owner")
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{new_member}", URI.encode_www_form({ role: "Data scientist"}), { content_type: 'application/x-www-form-urlencoded'}
          expect_json(successMessage: "Role updated successfully.")
          expect_status_details(200)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == new_member }
          expect(memb[:teamRole]).to eq ("Data scientist")
        end
        it "should update member project role in the kube config map" do
          if !kserve_installed
            skip "This test only runs with KServe installed"
          end
          new_member = create_user
          email = new_member[:email]
          username = new_member[:username]
          add_member(email, "Data owner")
          cm = get_project_teams_kube_config_map(@project[:projectname])
          expect(cm).not_to be_empty
          expect(cm).to include("data")
          expect(cm["data"]).to include(username)
          expect(cm["data"][username]).to eql "Data owner"

          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{email}", URI.encode_www_form({ role: "Data scientist"}), { content_type: 'application/x-www-form-urlencoded'}
          expect_json(successMessage: "Role updated successfully.")
          expect_status_details(200)
          cm = get_project_teams_kube_config_map(@project[:projectname])
          expect(cm).not_to be_empty
          expect(cm).to include("data")
          expect(cm["data"]).to include(username)
          expect(cm["data"][username]).to eql "Data scientist"
        end
        it "should change member role to Data owner" do
          new_member = create_user[:email]
          add_member(new_member, "Data scientist")
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{new_member}", URI.encode_www_form({ role: "Data owner"}), { content_type: 'application/x-www-form-urlencoded'}
          expect_json(successMessage: "Role updated successfully.")
          expect_status_details(200)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == new_member }
          expect(memb[:teamRole]).to eq ("Data owner")
        end
        it "should fail to change the role of the project owner" do
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers/#{@project[:username]}", URI.encode_www_form({ role: "Data scientist"}), { content_type: 'application/x-www-form-urlencoded'}
          expect_status_details(403, error_code: 150014)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb = json_body.detect { |e| e[:user][:email] == @project[:username] }
          expect(memb[:teamRole]).to eq ("Data owner")
        end
        it "should add multiple members" do
          member_1 = create_user[:email]
          member_2 = create_user[:email]
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers", {projectTeam: [{projectTeamPK: {projectId: @project[:id],teamMember: member_1},teamRole: "Data scientist"},{projectTeamPK: {projectId: @project[:id],teamMember: member_2},teamRole: "Data owner"}]}
          expect_json(successMessage: "Members added successfully")
          expect_status_details(200)
          get "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers"
          memb1 = json_body.detect { |e| e[:user][:email] == member_1 }
          memb2 = json_body.detect { |e| e[:user][:email] == member_2 }
          expect(memb1).to be_present
          expect(memb2).to be_present
        end
        it "should add multiple members to kube config map" do
          if !kserve_installed
            skip "This test only runs with KServe installed"
          end
          member_1 = create_user
          member_2 = create_user
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers", {projectTeam: [
          {projectTeamPK: {projectId: @project[:id],teamMember: member_1[:email]},teamRole: "Data scientist"},
          {projectTeamPK: {projectId: @project[:id],teamMember: member_2[:email]},teamRole: "Data owner"}]}
          expect_json(successMessage: "Members added successfully")
          expect_status_details(200)

          cm = get_project_teams_kube_config_map(@project[:projectname])
          expect(cm).not_to be_empty
          expect(cm).to include("data")

          expect(cm["data"]).to include(member_1[:username])
          expect(cm["data"][member_1[:username]]).to eql "Data scientist"

          expect(cm["data"]).to include(member_2[:username])
          expect(cm["data"][member_2[:username]]).to eql "Data owner"
        end
        it "should copy kube secrets when adding multiple members" do
          if !kserve_installed
            skip "This test only runs with KServe installed"
          end
          member_1 = create_user
          member_2 = create_user
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers", {projectTeam: [
          {projectTeamPK: {projectId: @project[:id],teamMember: member_1[:email]},teamRole: "Data scientist"},
          {projectTeamPK: {projectId: @project[:id],teamMember: member_2[:email]},teamRole: "Data owner"}]}
          expect_json(successMessage: "Members added successfully")
          expect_status_details(200)

          secret_1 = get_api_key_kube_project_serving_secret(@project[:projectname], member_1[:username])
          expect(secret_1).not_to be_nil
          expect(secret_1).to include("data")
          expect(secret_1["data"]).to include("apiKey")

          secret_2 = get_api_key_kube_project_serving_secret(@project[:projectname], member_2[:username])
          expect(secret_2).not_to be_nil
          expect(secret_2).to include("data")
          expect(secret_2["data"]).to include("apiKey")
        end
        it "should not add non-existing user" do
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers", {projectTeam: [{projectTeamPK: {projectId: @project[:id],teamMember: "none_existing_user@email.com"},teamRole: "Data scientist"}]}
          expect_status_details(400)
          field_errors = json_body[:usrMsg]
          expect(field_errors).to include("none_existing_user@email.com was not found in the system.")
        end
        it "should exclude non-existing user but add existing one" do
          new_member = create_user[:email]
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers", {projectTeam: [{projectTeamPK: {projectId: @project[:id],teamMember: "none_existing_user@email.com"},teamRole: "Data scientist"},{projectTeamPK: {projectId: @project[:id],teamMember: new_member},teamRole: "Data scientist"}]}
          expect_status_details(400)
          field_errors = json_body[:usrMsg]
          expect(field_errors).to include("none_existing_user@email.com was not found in the system.")
        end
        it "should not add existing member" do
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers", {projectTeam: [{projectTeamPK: {projectId: @project[:id], teamMember: "#{@project[:username]}"},teamRole: "Data scientist"}]}
          expect_status_details(400)
          field_errors = json_body[:usrMsg]
          expect(field_errors).to include("#{@project[:username]} is already a member in this project.")
        end
        it "should not add existing member but add non-existing one" do
          new_member = create_user[:email]
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers", {projectTeam: [{projectTeamPK: {projectId: @project[:id], teamMember: "#{@project[:username]}"},teamRole: "Data scientist"},{projectTeamPK: {projectId: @project[:id],teamMember: new_member},teamRole: "Data scientist"}]}
          expect_status_details(400)
          field_errors = json_body[:usrMsg]
          expect(field_errors).to include("#{@project[:username]} is already a member in this project.")
        end
        it "should allow a new member with sufficient privilege (Data owner) to add a member" do
          member = create_user
          new_member = create_user[:email]
          add_member(member[:email], "Data owner")
          create_session(member[:email],"Pass123")
          post "#{ENV['HOPSWORKS_API']}/project/#{@project[:id]}/projectMembers", {projectTeam: [{projectTeamPK: {projectId: @project[:id], teamMember: new_member},teamRole: "Data scientist"}]}
          expect_status_details(200)
          expect_json(successMessage: "One member added successfully")
        end
      end
    end
  end
end
