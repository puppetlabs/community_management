#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'optparse'
require_relative 'octokit_utils'

class PuppetModule
  attr_accessor :name, :namespace, :tag_date, :commits, :downloads
  def initialize(name, namespace, tag_date, commits, downloads = 0)
    @name = name
    @namespace = namespace
    @tag_date = tag_date
    @commits = commits
    @downloads = downloads
  end
end

def get_number_of_prs_by_label(util, prs, label, mod)
  nr = 0
  prs.each do |pr_since_tag|
    label_of_pr = util.does_pr_have_label((mod['github']).to_s, pr_since_tag[:pull][:number], label)
    nr += 1 if label_of_pr == true && !pr_since_tag[:pull][:merged_at].nil?
  end
  nr
end

puppet_modules = []
def number_of_downloads(slug)
  uri = URI.parse("https://forgeapi.puppetlabs.com/v3/modules/#{slug}")
  request =  Net::HTTP::Get.new(uri.path)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http| # pay attention to use_ssl if you need it
    http.request(request)
  end
  output = response.body
  parsed = JSON.parse(output)

  begin
    parsed['current_release']['downloads']
  rescue NoMethodError
    "Error number of downloads #{slug}"
  end
end

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
  exit
end

uri = URI.parse(options[:url])
response = Net::HTTP.get_response(uri)
output = response.body
parsed = JSON.parse(output)
util = OctokitUtils.new(options[:oauth])

repo_data = []

parsed.each do |_k, v|
  limit = util.client.rate_limit!
  puts "Getting data from Github API for #{v['github']}"
  if limit.remaining == 0
    #  sleep 60 #Sleep between requests to prevent Github API - 403 response
    sleep limit.resets_in
    puts 'Waiting for rate limit reset in Github API'
  end
  sleep 2 # Keep Github API happy

  latest_tag = util.fetch_tags((v['github']).to_s, options).first
  tag_ref = util.ref_from_tag(latest_tag)
  date_of_tag = util.date_of_ref((v['github']).to_s, tag_ref)
  commits_since_tag = util.commits_since_date_c((v['github']).to_s, date_of_tag)
  prs_since_tag = util.fetch_async((v['github']).to_s, options = { state: 'closed', sort: 'updated-desc' }, %i[statuses pull_request_commits issue_comments], attribute: 'closed_at', date: date_of_tag)

  no_maintenance_prs = get_number_of_prs_by_label(util, prs_since_tag, 'maintenance', v)
  no_feature_prs = get_number_of_prs_by_label(util, prs_since_tag, 'feature', v)
  no_bugfix_prs = get_number_of_prs_by_label(util, prs_since_tag, 'bugfix', v)
  no_incompatible_prs = get_number_of_prs_by_label(util, prs_since_tag, 'backwards-incompatible', v)

  repo_data << { 'repo' => (v['github']).to_s, 'date' => date_of_tag, 'commits' => commits_since_tag.size, 'downloads' => number_of_downloads(v['slug']), 'maintenance_prs' => no_maintenance_prs, 'feature_prs' => no_feature_prs, 'bugfix_prs' => no_bugfix_prs, 'incompatible_prs' => no_incompatible_prs }
  puppet_modules << PuppetModule.new(repo, (v['github']).to_s, date_of_tag, commits_since_tag)
rescue StandardError
  puts "Unable to fetch tags for #{options[:namespace]}/#{repo}" if options[:verbose]
end
sleep(2)

html = ERB.new(File.read('release_planning.html.erb')).result(binding)
File.open('ModulesRelease.html', 'wb') do |f|
  f.puts(html)
end
