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
parsed.each do |_k, v|
  limit = util.client.rate_limit!
  puts "Getting data from Github API for #{v['github']}"
  if limit.remaining == 0
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
    puts url
    next unless wf['name'] == 'nightly'

    runs_json = RestClient.get(url, headers)
    runs = JSON.parse(runs_json)

    runs['workflow_runs'].each do |run|
      export_results = []
      jobs_json = JSON.parse(RestClient.get(run['jobs_url'], headers))
      jobs_json['jobs'].each do |job|
        next unless job['name'].include?('Acceptance')

        matches = job['name'].match(/Acceptance \((?<os>[a-z0-9_.-]*), (?<agent>[a-z0-9_.-]*)\)/)
        export_results << {
          "os": matches[:os],
          "agent": matches[:agent],
          "result": job['conclusion']
        }
      end
      runs_array << {
        "run_number": run['run_number'],
        "html_url": run['html_url'],
        "head_branch": run['head_branch'],
        "os_agent": export_results
      }
    end
    result_hash << {
      "url": "https://github.com/#{v['github']}",
      "name": v['title'],
      "runs": runs_array
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