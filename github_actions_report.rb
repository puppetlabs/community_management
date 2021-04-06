#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'json'
require 'rest-client'
require_relative 'octokit_utils'
require_relative 'options'
options = parse_options
parsed = load_url(options)
util = OctokitUtils.new(options[:oauth])
result_hash = []
headers = { Authorization: "token #{options[:oauth]}" }
count = 0

def parse_job(job,module_name)
  @general_conclusion = true if job['conclusion'] == 'failure'
  matches = job['name'].split(',')
  {
    "os": matches[0],
    "agent": matches[1][1..],
    "result": job['conclusion'],
    "url": "https://github.com/#{module_name}/runs/#{job['id']}?check_suite_focus=true" 
  }
end
parsed.each do |_k, v|
  limit = util.client.rate_limit!
  puts "Getting data from Github API for #{v['github']}"
  if limit.remaining.zero?
    #  sleep 60 #Sleep between requests to prevent Github API - 403 response
    sleep limit.resets_in
    puts 'Waiting for rate limit reset in Github API'
  end
  sleep 2 # Keep Github API happy
  url = "https://api.github.com/repos/#{v['github']}/actions/workflows"
  result = RestClient.get(url, headers)
  data = JSON.parse(result.body)
  runs_array = []
  data['workflows'].each do |wf|
    url = "https://api.github.com/repos/#{v['github']}/actions/workflows/#{wf['id']}/runs"
    next unless wf['name'] == 'nightly'

    runs_json = RestClient.get(url, headers)
    runs = JSON.parse(runs_json)
    runs['workflow_runs'][0..4].each do |run|
      @general_conclusion = false
      jobs_json = JSON.parse(RestClient.get(run['jobs_url'], headers))        
      os_agent = jobs_json['jobs'].select { |job| job['name'].include?('puppet') }.map { |job| parse_job(job, v['github']) }
      job_failures = os_agent.select { |x| x[:result] == 'failure' }.length
      job_successes = os_agent.select { |x| x[:result] == 'success' }.length
      runs_array << {
        "run_id": run['id'],
        "run_number": run['run_number'],
        "html_url": run['html_url'],
        "updated_at": run['updated_at'],
        "head_branch": run['head_branch'],
        "os_agent": os_agent.sort_by { |hash| hash[:agent] },
        "general_conclusion": @general_conclusion,
        "job_failures": job_failures,
        "job_successes": job_successes
      }
    end

    result_hash << {
      "url": "https://github.com/#{v['github']}",
      "name": v['title'],
      "runs": runs_array.sort_by {|hash| hash[:run_number]},
      "workflows": data['workflows'],
      "total_failures": runs_array.map { |x| x[:job_failures]}.reduce(0) { |sum, num| sum + num },
      "total_successes": runs_array.map { |x| x[:job_successes]}.reduce(0) { |sum, num| sum + num },
      "last_night_failures": runs_array[0][:job_failures], 
      "last_night_successes": runs_array[0][:job_successes]
    }
  end
rescue StandardError => e
  puts "#{v['title']} - Error: #{e}"

  result_hash << {
    "url": "https://github.com/#{v['github']}",
    "name": v['title'],
    "workflows": 'Not available',
    "runs": 'Not available',
    "agent": 'Not available',
    "os": 'Not available'
  }
end

html = ERB.new(File.read('github_actions_report.html.erb')).result(binding)
File.open('GithubActionsReport.html', 'wb') do |f|
  f.puts(html)
end
js = ERB.new(File.read('github_action_report.js.erb')).result(binding)
File.open('github_action_report.js', 'wb') do |f|
  f.puts(js)
end
