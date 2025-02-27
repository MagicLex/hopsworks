=begin
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
=end

describe "On #{ENV['OS']}" do
  before :all do
    @max_executions_per_job = getVar('executions_per_job_limit').value
    @debugOpt=false
    # Enable the reporting
    RSpec.configure do |c|
      c.example_status_persistence_file_path  = 'execution_debug.txt' if @debugOpt
    end
  end
  after(:all) {clean_all_test_projects(spec: "execution")}

  describe 'execution core' do
    context 'create' do
      context 'without authentication' do
        before :all do
          with_valid_project
          reset_session
        end
        it "should fail" do
          create_sparktour_job(@project, "demo_job", 'jar', expected_status: 401, error_code: 200003)
        end
      end
      job_types = ['jar', 'py', 'ipynb']
      job_types.each do |type|
        context 'with authentication and executable ' + type do
          before :all do
            setVar('executions_per_job_limit', '2')
            with_valid_tour_project("spark")
          end
          after :all do
            setVar('executions_per_job_limit', @max_executions_per_job)
          end
          after :each do
            clean_jobs(@project[:id])
          end

          it "should start a job and get its executions" do
            #create job
            $job_name_1 = "demo_job_1_" + type
            create_sparktour_job(@project, $job_name_1, type)
            job_id = json_body[:id]
            #start execution
            start_execution(@project[:id], $job_name_1)
            execution_id = json_body[:id]
            begin
              expect(json_body[:state]).to eq "INITIALIZING"
              #get execution
              get_execution(@project[:id], $job_name_1, json_body[:id])
              expect(json_body[:id]).to eq(execution_id)
            ensure
              #wait till it's finished and start second execution
              wait_for_execution_completed(@project[:id], $job_name_1, json_body[:id], "FINISHED")
            end
            #start execution
            start_execution(@project[:id], $job_name_1)
            execution_id = json_body[:id]
            begin
              #get all executions of job
              get_executions(@project[:id], $job_name_1)
              expect(json_body[:items].count).to eq 2

              #check database
              num_executions = count_executions(job_id)
              expect(num_executions).to eq 2
            ensure
              wait_for_execution_completed(@project[:id], $job_name_1, execution_id, "FINISHED")
            end
          end
          it "should start and stop job" do
            $job_name_2 = "demo_job_2_" + type
            create_sparktour_job(@project, $job_name_2, type)

            #start execution
            start_execution(@project[:id], $job_name_2)
            execution_id = json_body[:id]
            begin
              wait_for_execution_active(@project[:id], $job_name_2, execution_id, "ACCEPTED", "appId")
              stop_execution(@project[:id], $job_name_2, execution_id)
            ensure
              wait_for_execution_completed(@project[:id], $job_name_2, execution_id, "KILLED")
            end
          end
          it "should start two executions in parallel" do
            $job_name_3 = "demo_job_3_" + type
            create_sparktour_job(@project, $job_name_3, type)
            begin
              start_execution(@project[:id], $job_name_3)
              execution_id1 = json_body[:id]
              start_execution(@project[:id], $job_name_3)
              execution_id2 = json_body[:id]
            ensure
              wait_for_execution_completed(@project[:id], $job_name_3, execution_id1, "FINISHED") unless execution_id1.nil?
              wait_for_execution_completed(@project[:id], $job_name_3, execution_id2, "FINISHED") unless execution_id2.nil?
            end
          end
          it "should start a job, delete it and cleanup its executions" do
            #create job
            job_name = "demo_job"
            create_sparktour_job(@project, job_name, 'jar')
            job_id = json_body[:id]
            #start execution
            start_execution(@project[:id], job_name)
            execution_id = json_body[:id]
            #wait till it's finished and start second execution
            wait_for_execution_completed(@project[:id], job_name, execution_id, "ACCEPTED")
            #start execution
            start_execution(@project[:id], job_name)
            execution_id = json_body[:id]
            wait_for_execution_completed(@project[:id], job_name, execution_id, "ACCEPTED")

            # Delete job
            delete_job(@project[:id], job_name)
            #Wait for executions to be deleted
            sleep(getVar("executions_cleaner_interval_ms").value.to_i * 2/1000)

            #check database
            num_executions = count_executions(job_id)
            expect(num_executions).to eq 0
          end
          it "should start an execution and delete it while running" do
            job_name = "demo_job_5_" + type
            create_sparktour_job(@project, job_name, type)
            #start execution
            start_execution(@project[:id], job_name)
            execution_id = json_body[:id]
            wait_for_execution_active(@project[:id], job_name, execution_id, "ACCEPTED", "appId")
            get_execution(@project[:id], job_name, execution_id)
            app_id = json_body[:appId]
            delete_execution(@project[:id], job_name, execution_id)

            #check database
            num_executions = count_executions(job_name)
            expect(num_executions).to eq 0

            #Check YARN that the app_id was killed
            wait_for_yarn_app_state(app_id, "KILLED")
          end
          def get_logs(project, job_name, execution_id, application_id, hdfs_user, log_type)
            wait_for_me_time(60) do
              get_execution_log(project[:id], job_name, execution_id, log_type)
              found_state = json_body.key?(:log) && json_body[:log] != "No log available."
              { 'success' => found_state, 'msg' => "Timed-out waiting for #{log_type} log aggregation", "result" => json_body}
            end
            expect_status_details(200)
            unless check_log_dir_has_files(hdfs_user, application_id)
              raise "Log aggregation failed in YARN"
            end
            expect(json_body[:log]).not_to eq("No log available.")
            pp "execution json_body: #{json_body}" if defined?(@debugOpt) && @debugOpt
            expect(json_body[:type]).to eq log_type.upcase
          end
          def run_job_and_get_logs(project, job_name)
            start_execution(project[:id], job_name)
            execution_id = json_body[:id]
            hdfs_user = json_body[:hdfsUser]
            wait_for_execution_completed(project[:id], job_name, execution_id, "FINISHED")
            get_execution(project[:id], job_name, execution_id)
            application_id = json_body[:appId]

            get_logs(project, job_name, execution_id, application_id, hdfs_user, "out")
            get_logs(project, job_name, execution_id, application_id, hdfs_user, "err")
          end
          it "should run a job and get out and err logs" do
            $job_name_4 = "demo_job_4_" + type
            create_sparktour_job(@project, $job_name_4, type)
            run_job_and_get_logs(@project, $job_name_4)

            member = create_user
            add_member_to_project(@project, member[:email], "Data scientist")
            create_session(member[:email], "Pass123")
            run_job_and_get_logs(@project, $job_name_4)
          end
        end
      end
    end
  end
  describe 'execution extended', if: false do
    context 'create' do
      job_types = ['jar', 'py', 'ipynb']
      job_types.each do |type|
        context 'with authentication and executable ' + type do
        before :all do
          setVar('executions_per_job_limit', '2')
          with_valid_tour_project("spark")
        end
        after :all do
          setVar('executions_per_job_limit', @max_executions_per_job)
        end
        after :each do
          clean_jobs(@project[:id])
        end

        it "should fail to start a spark job with missing spark.yarn.dist.files" do
          $job_name_2 = "demo_job_2_" + type
          create_sparktour_job(@project, $job_name_2, type)
          config = json_body[:config]
          config[:'spark.yarn.dist.files'] = "hdfs:///Projects/#{@project[:projectname]}/Resources/iamnothere.txt"
          create_sparktour_job(@project, $job_name_2, type, job_conf: config, expected_status: 200)
          #start execution
          start_execution(@project[:id], $job_name_2, expected_status: 400)
        end
        it "should fail to start a spark job with missing spark.yarn.dist.pyFiles" do
          $job_name_2 = "demo_job_2_" + type
          create_sparktour_job(@project, $job_name_2, type)
          config = json_body[:config]
          config[:'spark.yarn.dist.pyFiles'] = "hdfs:///Projects/#{@project[:projectname]}/Resources/iamnothere.py"
          create_sparktour_job(@project, $job_name_2, type, job_conf: config, expected_status: 200)
          #start execution
          start_execution(@project[:id], $job_name_2, expected_status: 400)
        end
        it "should fail to start a spark job with missing spark.yarn.dist.jars" do
          $job_name_2 = "demo_job_2_" + type
          create_sparktour_job(@project, $job_name_2, type)
          config = json_body[:config]
          config[:'spark.yarn.dist.jars'] = "hdfs:///Projects/#{@project[:projectname]}/Resources/iamnothere.jar"
          create_sparktour_job(@project, $job_name_2, type, job_conf: config, expected_status: 200)
          #start execution
          start_execution(@project[:id], $job_name_2, expected_status: 400)
        end
        it "should fail to start a spark job with missing spark.yarn.dist.archives" do
          $job_name_2 = "demo_job_2_" + type
          create_sparktour_job(@project, $job_name_2, type)
          config = json_body[:config]
          config[:'spark.yarn.dist.archives'] = "hdfs:///Projects/#{@project[:projectname]}/Resources/iamnothere.zip"
          create_sparktour_job(@project, $job_name_2, type, job_conf: config, expected_status: 200)

          #start execution
          start_execution(@project[:id], $job_name_2, expected_status: 400)
        end
        it "should not start more than the allowed maximum number of executions per job" do
          $job_name_3 = "demo_job_3_" + type
          create_sparktour_job(@project, $job_name_3, type)
          begin
            start_execution(@project[:id], $job_name_3)
            execution_id1 = json_body[:id]
            start_execution(@project[:id], $job_name_3)
            execution_id2 = json_body[:id]
            start_execution(@project[:id], $job_name_3, expected_status: 400, error_code: 130040)
          ensure
            wait_for_execution_completed(@project[:id], $job_name_3, execution_id1, "FINISHED") unless execution_id1.nil?
            wait_for_execution_completed(@project[:id], $job_name_3, execution_id2, "FINISHED") unless execution_id2.nil?
          end
        end
        it "should start a job and use default args" do
          $job_name_3 = "demo_job_3_" + type
          create_sparktour_job(@project, $job_name_3, type)
          default_args = json_body[:config][:defaultArgs]
          start_execution(@project[:id], $job_name_3)
          execution_id = json_body[:id]
          begin
            get_execution(@project[:id], $job_name_3, execution_id)
            expect(json_body[:args]).not_to be_nil
            expect(default_args).not_to be_nil
            expect(json_body[:args]).to eq default_args
          ensure
            wait_for_execution_completed(@project[:id], $job_name_3, execution_id, "FINISHED")
          end
        end
        it "should start a job with args 123" do
          $job_name_3 = "demo_job_3_" + type
          create_sparktour_job(@project, $job_name_3, type)
          args = "123"
          start_execution(@project[:id], $job_name_3, args: args)
          execution_id = json_body[:id]
          begin
            get_execution(@project[:id], $job_name_3, execution_id)
            expect(json_body[:args]).to eq args
          ensure
            wait_for_execution_completed(@project[:id], $job_name_3, execution_id, "FINISHED")
          end
        end
      end
      end

      describe 'execution with checking nodemanager status enabled' do
        context 'with authentication and executable'  do
          oldStatus = nil
          hostnames = Array.new
          before :all do
            with_valid_tour_project("spark")
            oldStatus = getVar("check_nodemanagers_status")
            expect_status(200)
            with_admin_session()
            nodemanagers_request = get "#{ENV['HOPSWORKS_API']}/services/nodemanager"
            expect_status(200)
            nodemanagers = JSON.parse(nodemanagers_request)["items"]
            expect(nodemanagers != nil)
            nodemanagers.each do |nodemanager|
              hostnames.push(find_by_host_id(nodemanager["hostId"]).hostname)
            end
            reset_session
          end
          after :each do
            setVar("check_nodemanagers_status", oldStatus.value.to_s)
            with_admin_session()
            hostnames.each do |hostname|
              hosts_update_host_service(hostname, "nodemanager", "SERVICE_START")
              expect_status(200)
            end
            reset_session
            create_session(@project[:username],"Pass123")
            clean_jobs(@project[:id])
            reset_session
          end
          it 'Should fail to run a job if nodemanager is disabled and checking of nodemanager status is enabled' do
            type = job_types[0]
            job_name_3 = "demo_job_3_" + type
            create_session(@project[:username],"Pass123")
            create_sparktour_job(@project, job_name_3, type)
            reset_session
            with_admin_session()
            hostnames.each do |hostname|
              hosts_update_host_service(hostname, "nodemanager", "SERVICE_STOP")
            end
            setVar("check_nodemanagers_status", 'true')
            sleep(20)
            reset_session
            create_session(@project[:username],"Pass123")
            start_execution(@project[:id], job_name_3, expected_status: 503, error_code: 130030)
          end
        end
      end
      describe 'execution sort, filter, offset and limit' do
        $job_spark_1 = "demo_job_1"
        $execution_ids = []
        context 'with authentication' do
          before :all do
            with_valid_tour_project("spark")
            create_sparktour_job(@project, $job_spark_1, 'jar')
            #start 3 executions
            for i in 0..2 do
              start_execution(@project[:id], $job_spark_1)
              $execution_ids.push(json_body[:id])
              #wait till it's finished and start second execution
              wait_for_execution_completed(@project[:id], $job_spark_1, json_body[:id], "FINISHED")
            end
          end
          after :all do
            clean_jobs(@project[:id])
          end
          describe "Executions sort" do
            it "should get all executions sorted by id asc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:id]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=id:asc")
              sorted_res = json_body[:items].map {|execution| execution[:id]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by id desc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:id]}
              sorted = executions.sort.reverse
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=id:desc")
              sorted_res = json_body[:items].map {|execution| execution[:id]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by submissiontime asc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:submissionTime]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=submissiontime:asc")
              sorted_res = json_body[:items].map {|execution| execution[:submissionTime]}
              time_expect_to_be_eq(sorted_res, sorted)
            end
            it "should get all executions sorted by submissiontime desc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:submissionTime]}
              sorted = executions.sort.reverse
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=submissiontime:desc")
              sorted_res = json_body[:items].map {|execution| execution[:submissionTime]}
              time_expect_to_be_eq(sorted_res, sorted)
            end
            it "should get all executions sorted by state asc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:state]}
              sorted = executions.sort_by(&:downcase)
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=state:asc")
              sorted_res = json_body[:items].map {|execution| execution[:state]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by state desc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:state]}
              sorted = executions.sort_by(&:downcase).reverse
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=state:desc")
              sorted_res = json_body[:items].map {|execution| execution[:state]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by finalStatus asc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:finalStatus]}
              sorted = executions.sort_by(&:downcase)
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=finalStatus:asc")
              sorted_res = json_body[:items].map {|execution| execution[:finalStatus]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by finalStatus desc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:finalStatus]}
              sorted = executions.sort_by(&:downcase).reverse
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=finalStatus:desc")
              sorted_res = json_body[:items].map {|execution| execution[:finalStatus]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by appId asc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:appId]}
              sorted = executions.sort_by(&:downcase)
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=appId:asc")
              sorted_res = json_body[:items].map {|execution| execution[:appId]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by appId desc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:appId]}
              sorted = executions.sort_by(&:downcase).reverse
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=appId:desc")
              sorted_res = json_body[:items].map {|execution| execution[:appId]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by progress asc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:progress]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=progress:asc")
              sorted_res = json_body[:items].map {|execution| execution[:progress]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by progress desc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:progress]}
              sorted = executions.sort.reverse
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=progress:desc")
              sorted_res = json_body[:items].map {|execution| execution[:progress]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by duration asc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:duration]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=duration:asc")
              sorted_res = json_body[:items].map {|execution| execution[:duration]}
              expect(sorted_res).to eq(sorted)
            end
            it "should get all executions sorted by duration desc" do
              #sort in memory and compare with query
              #get all executions of job
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:duration]}
              sorted = executions.sort.reverse
              get_executions(@project[:id], $job_spark_1, query: "?sort_by=duration:desc")
              sorted_res = json_body[:items].map {|execution| execution[:duration]}
              expect(sorted_res).to eq(sorted)
            end
          end
          describe "Executions offset, limit" do
            it 'should return limit=x executions.' do
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:id]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?limit=2&sort_by=id:asc")
              sorted_res = json_body[:items].map {|execution| execution[:id]}
              expect(sorted_res).to eq(sorted.take(2))
            end
            it 'should return executions starting from offset=y.' do
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:id]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?offset=1&sort_by=id:asc")
              sorted_res = json_body[:items].map {|execution| execution[:id]}
              expect(sorted_res).to eq(sorted.drop(1))
            end
            it 'should return limit=x executions with offset=y.' do
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:id]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?offset=1&limit=2&sort_by=id:asc")
              sorted_res = json_body[:items].map {|execution| execution[:id]}
              expect(sorted_res).to eq(sorted.drop(1).take(2))
            end
            it 'should ignore if limit < 0.' do
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:id]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?limit=-2&sort_by=id:asc")
              sorted_res = json_body[:items].map {|execution| execution[:id]}
              expect(sorted_res).to eq(sorted)
            end
            it 'should ignore if offset < 0.' do
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:id]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?offset=-1&sort_by=id:asc")
              sorted_res = json_body[:items].map {|execution| execution[:id]}
              expect(sorted_res).to eq(sorted)
            end
            it 'should ignore if limit = 0.' do
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:id]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?limit=0&sort_by=id:asc")
              sorted_res = json_body[:items].map {|execution| execution[:id]}
              expect(sorted_res).to eq(sorted)
            end
            it 'should ignore if offset = 0.' do
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:id]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?offset=0&sort_by=id:asc")
              sorted_res = json_body[:items].map {|execution| execution[:id]}
              expect(sorted_res).to eq(sorted)
            end
            it 'should ignore if limit=0 and offset = 0.' do
              get_executions(@project[:id], $job_spark_1)
              executions = json_body[:items].map {|execution| execution[:id]}
              sorted = executions.sort
              get_executions(@project[:id], $job_spark_1, query: "?offset=0&limit=0&sort_by=id:asc")
              sorted_res = json_body[:items].map {|execution| execution[:id]}
              expect(sorted_res).to eq(sorted)
            end
          end
          describe "Executions filter" do
            it "should get all executions filtered by state" do
              get_executions(@project[:id], $job_spark_1, query: "?filter_by=state:finished")
              json_body[:items].map {|execution| execution[:id]}
              expect(json_body[:items].count).to eq 3
            end
            it "should get all executions filtered by state_neq" do
              get_executions(@project[:id], $job_spark_1, query: "?filter_by=state_neq:finished")
              expect(json_body[:items]).to be nil
            end
            it "should get all executions filtered by finalStatus" do
              get_executions(@project[:id], $job_spark_1, query: "?filter_by=finalstatus:succeeded")
              json_body[:items].map {|execution| execution[:id]}
              expect(json_body[:items].count).to eq 3
            end
            it "should get all executions filtered by finalStatus_neq" do
              get_executions(@project[:id], $job_spark_1, query: "?filter_by=finalstatus_neq:succeeded")
              expect(json_body[:items]).to be nil
            end
            it "should get all executions filtered by submissiontime" do
              #get submissiontime of last execution
              get_execution(@project[:id], $job_spark_1, $execution_ids[0])
              submissiontime = json_body[:submissionTime]
              get_executions(@project[:id], $job_spark_1, query: "?filter_by=submissiontime:#{submissiontime}")
              expect_status_details(200)
              expect(json_body[:items].count).to eq 1
            end
            it "should get all executions filtered by submissiontime gt" do
              #get submissiontime of last execution
              get_execution(@project[:id], $job_spark_1, $execution_ids[0])
              submissiontime = json_body[:submissionTime]
              get_executions(@project[:id], $job_spark_1, query: "?filter_by=submissiontime_gt:#{submissiontime}")
              expect_status_details(200)
              expect(json_body[:items].count).to eq 2
            end
            it "should get all executions filtered by submissiontime lt" do
              #get submissiontime of last execution
              get_execution(@project[:id], $job_spark_1, $execution_ids[1])
              submissiontime = json_body[:submissionTime]
              get_executions(@project[:id], $job_spark_1, query: "?filter_by=submissiontime_lt:#{submissiontime}")
              expect_status_details(200)
              expect(json_body[:items].count).to eq 1
            end
          end
        end
      end
    end
    describe "#quota" do
      before :all do
        @cookies = with_admin_session
        with_valid_tour_project("spark")
      end

      after :all do
        @cookies = nil
      end

      it 'should not be able to run jobs with 0 quota and payment type PREPAID' do
        set_yarn_quota(@project, 0)
        set_payment_type(@project, "PREPAID")
        create_sparktour_job(@project, "quota1", 'jar')
        start_execution(@project[:id], "quota1", expected_status: 412)
      end
      it 'should not be able to run jobs with negative quota and payment type PREPAID' do
        set_yarn_quota(@project, -10)
        set_payment_type(@project, "PREPAID")
        create_sparktour_job(@project, "quota2", 'jar')
        start_execution(@project[:id], "quota2", expected_status: 412)
      end
      it 'should not kill the running job if the quota goes negative' do
        set_yarn_quota(@project, 1)
        set_payment_type(@project, "PREPAID")
        create_sparktour_job(@project, "quota3", 'jar')
        run_execution(@project[:id], "quota3")
      end
      it 'should be able to run jobs with 0 quota and payment type NOLIMIT' do
        set_yarn_quota(@project, 0)
        set_payment_type(@project, "NOLIMIT")
        create_sparktour_job(@project, "quota4", 'jar')
        run_execution(@project[:id], "quota4")
      end
      it 'should be able to run jobs with negative quota and payment type NOLIMIT' do
        set_yarn_quota(@project, -10)
        set_payment_type(@project, "NOLIMIT")
        create_sparktour_job(@project, "quota5", 'jar')
        run_execution(@project[:id], "quota5")
      end
      describe "#parallel executions" do
        before :all do
          setVar("quotas_max_parallel_executions", "1")
          @cookies_pe = with_admin_session
          with_valid_tour_project("spark")
        end
        after :all do
          setVar("quotas_max_parallel_executions", "-1")
          @cookies_pe = nil
        end
        it "should not launch more than configured max parallel executions" do
          create_sparktour_job(@project, "max_parallel_exec", "jar")
          start_execution(@project[:id], "max_parallel_exec")

          # reached limit
          resp = start_execution(@project[:id], "max_parallel_exec", expected_status: 400)
          parsed = JSON.parse(resp)
          expect(parsed['usrMsg']).to include("quota")
        end
      end
    end
    describe '#access' do
      before :all do
        @user_data_owner = create_user
        pp @user_data_owner[:email] if defined?(@debugOpt) && @debugOpt
        @user_data_scientist = create_user
        @user_other = create_user
        create_session(@user_data_owner[:email], "Pass123")
        @project = create_project
        add_member_to_project(@project, @user_data_scientist[:email], "Data scientist")
        @job_name = "test_job_#{short_random_id}"

        run_job(@user_data_owner, @project, @job_name)
      end

      def setup_job(user, project, job_name)
        chmod_local_dir("#{ENV['PROJECT_DIR']}", 777, true)
        src_dir = "#{ENV['PROJECT_DIR']}/hopsworks-IT/src/test/ruby/spec/auxiliary"
        src = "#{src_dir}/hello_world.py"
        dst = "/Projects/#{project[:projectname]}/Resources/#{job_name}.py"
        group = "#{project[:projectname]}__Resources"
        copy_from_local(src, dst, user[:username], group, 750, "#{project[:projectname]}")
        job_config = get_spark_default_py_config(project, job_name, "py")
        create_sparktour_job(project, job_name, "py", job_conf: job_config)
      end
      def run_job(user, project, job_name)
        begin
          get_job(project["id"], job_name, expected_status: 200)
        rescue RSpec::Expectations::ExpectationNotMetError => e
          if job_does_not_exist
            setup_job(user, project, job_name)
            start_execution(project["id"], job_name)
          end
        end
      end
      def get_execution(project, job_name)
        get_executions(project["id"], job_name)
        expect(json_body[:items].length).to be > 0
        json_body[:items][0]
      end

      proxied_pages = [
        {:type => "spark main",
         :uri => lambda {|app_id, attempt_id|
           "/hopsworks-api/yarnui/https://resourcemanager.service.consul:8089/proxy/#{app_id}"}},
        {:type => "sql",
         :uri => lambda {|app_id, attempt_id|
           "/hopsworks-api/yarnui/https://resourcemanager.service.consul:8089/proxy/#{app_id}/SQL"}},
        {:type => "all executors",
         :uri => lambda {|app_id, attempt_id|
           "/hopsworks-api/yarnui/https://historyserver.spark.service.consul:18080/api/v1/applications/#{app_id}/#{attempt_id}/allexecutors"}},
        {:type => "executors",
         :uri => lambda {|app_id, attempt_id|
           "/hopsworks-api/yarnui/https://historyserver.spark.service.consul:18080/history/#{app_id}/#{attempt_id}/executors"}},
        {:type => "envirnoment",
         :uri => lambda {|app_id, attempt_id|
           "/hopsworks-api/yarnui/https://historyserver.spark.service.consul:18080/history/#{app_id}/#{attempt_id}/environment"}},
        {:type => "storage",
         :uri => lambda {|app_id, attempt_id|
           "/hopsworks-api/yarnui/https://historyserver.spark.service.consul:18080/history/#{app_id}/#{attempt_id}/storage"}},
        {:type => "stages",
         :uri => lambda {|app_id, attempt_id|
           "/hopsworks-api/yarnui/https://historyserver.spark.service.consul:18080/history/#{app_id}/#{attempt_id}/stages"}},
        {:type => "jobs",
         :uri => lambda {|app_id, attempt_id|
           "/hopsworks-api/yarnui/https://historyserver.spark.service.consul:18080/history/#{app_id}/#{attempt_id}/jobs"}}
      ]
      proxied_pages.each do |p|
        it 'data owner should see ' + p[:type] do
          raw_create_session(@user_data_owner[:email], "Pass123")
          execution = get_execution(@project, @job_name)
          uri = p[:uri].(execution[:appId], 1)
          pp "uri: #{uri}" if defined?(@debugOpt) && @debugOpt
          get uri
          expect_status_details(200)
        end
        it 'data scientist should see ' + p[:type] do
          raw_create_session(@user_data_scientist[:email], "Pass123")
          execution = get_execution(@project, @job_name)
          uri = p[:uri].(execution[:appId], 1)
          pp "uri: #{uri}" if defined?(@debugOpt) && @debugOpt
          get uri
          expect_status_details(200)
        end
        it 'other user should not see ' + p[:type] do
          raw_create_session(@user_data_owner[:email], "Pass123")
          execution = get_execution(@project, @job_name)
          raw_create_session(@user_other[:email], "Pass123")
          uri = p[:uri].(execution[:appId], 1)
          pp "uri: #{uri}" if defined?(@debugOpt) && @debugOpt
          get uri
          expect_status_details(400)
        end
      end
    end
  end
end