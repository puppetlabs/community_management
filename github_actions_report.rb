#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'rest-client'
require 'optparse'
require_relative 'octokit_utils'
require 'json'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: stats.rb [options]'
  opts.on('-u MANDATORY', '--url=MANDATORY', String, 'Link to json file for modules') { |v| options[:url] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
end

parser.parse!

options[:url] = 'https://puppetlabs.github.io/iac/modules.json' if options[:url].nil?
missing = []
missing << '-t' if options[:oauth].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

uri = URI.parse(options[:url])
response = Net::HTTP.get_response(uri)
output = response.body
parsed = JSON.parse(output)

util = OctokitUtils.new(options[:oauth])

result_hash = []
headers = { Authorization: "token #{options[:oauth]}" }

parsed.each do |k,v|
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

  runs = {}

  data['workflows'].each do |wf|
    url = "https://api.github.com/repos/#{v['github']}/actions/workflows/#{wf['id']}/runs"
    runs_json = RestClient.get(url, headers)
    runs[wf['name']] = JSON.parse(runs_json)
  end

  result_hash << {
    "url": "https://github.com/#{v['github']}",
    "name": v['title'],
    "workflows": data['workflows'],
    "runs": runs
  }
rescue StandardError => e
  puts "#{v['title']} - Error: #{e}"
  result_hash << {
    "url": "https://github.com/#{v['github']}",
    "name": v['title'],
    "workflows": 'Not available',
    "runs": 'Not available'
  }
end

html = ERB.new(File.read('github_actions_report.html.erb')).result(binding)

File.open('GithubActionsReport.html', 'wb') do |f|
  f.puts(html)
end
