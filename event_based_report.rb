#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'json'
require 'rest-client'
require 'fileutils'
require_relative 'octokit_utils'
require_relative 'options'
options = parse_options
util = OctokitUtils.new(options[:oauth])

client = util.client

owner = 'puppetlabs'
repo_name = 'puppetlabs-motd'
repo = "#{owner}/#{repo_name}"

#region Updating the Cache

puts "Processing #{repo}"
client.auto_paginate = false
last_pr_number = client.pull_requests(repo, state: 'all', sort: 'created', direction: 'desc', per_page: 1, page: 1).first.number
client.auto_paginate = true

# client.pull_requests(repo, state: 'all').each do |pull|
  # pull_nr = 404
  # pull_nr = pull.number
(1..last_pr_number+1).each do |pull_nr|
  puts "Processing #{pull_nr}"

  pull_dir = File.join('data', owner, repo_name, 'pulls', pull_nr.to_s)
  FileUtils.mkdir_p(pull_dir)

  pull_cache_file = File.join(pull_dir, "data.json")
  # load cache or set data to nil
  data = JSON.parse(File.read(pull_cache_file)) rescue nil
  # TODO: check for data freshness
  # load if cache failed loading
  data ||= client.pull_request(repo, pull_nr).to_h rescue {}

  # TODO: don't rewrite cache if it didn't change
  File.open(pull_cache_file, 'w') {|f| f.write(JSON.pretty_generate(data)) }

  pull_timeline_cache_file = File.join(pull_dir, "timeline.json")
  timeline = JSON.parse(File.read(pull_timeline_cache_file)) rescue nil
  # TODO: check for data freshness
  # load if cache failed loading
  timeline ||= client.issue_timeline(repo, pull_nr, accept: 'application/vnd.github.mockingbird-preview').map(&:to_h) rescue nil
  # TODO: don't rewrite cache if it didn't change
  # TODO: change this to line-per-item serialisation, for future updates through webhook events
  File.open(pull_timeline_cache_file, 'w') {|f| f.write(JSON.pretty_generate(timeline)) }

  # puts pull
end

#endregion


#region Loading Data into memory

# data/puppetlabs/puppetlabs-motd/pulls/417
PULLS = Dir['data/*/*/pulls/*']

require 'algorithms'

# this will collect [event, timestamp] pairs for efficient sorting at the end
events_by_last_updated = []

PULLS.each do |pull_dir|
  data = JSON.parse(File.read(File.join(pull_dir, "data.json")))
  next if data == {}
  data["event"] = "pr_created"
  data["TS"] = Time.parse(data["created_at"])
  # use negative seconds from created_at to have oldest events first
  events_by_last_updated << [data, -data["TS"].to_i]
  timeline = JSON.parse(File.read(File.join(pull_dir, "timeline.json")))
  timeline.each do |event|
    case event["event"]
    when 'commit-commented', 'line-commented'
      event["comments"].each do |comment|
        comment["event"] = event["event"]
        comment["event_data"] = event
        comment["pull"] = data
        comment["TS"] = Time.parse(comment["created_at"])
        events_by_last_updated << [comment, -comment["TS"].to_i]
      end
    else
      event["pull"] = data
      event["TS"] = Time.parse(event["created_at"] || event["submitted_at"] || event.dig("committer", "date"))
        events_by_last_updated << [event, -event["TS"].to_i]
    end
  rescue
    require'pry';binding.pry
  end
end

# sort and unwrap
events_by_last_updated = events_by_last_updated.sort{|a,b| a[1] <=> b[1] }.map{|e| e[0] }

#endregion

#region Processing data stream

class Processor
  def record_day(database, date)
    database[:prs_by_day] ||= {}
    database[:prs_by_day][date] = {}
    [:prs_created, :prs_merged, :prs_closed].each do |metric|
      database[:prs_by_day][date][metric] = database[metric]
      database[metric] = 0
    end
  end

  def do_pr_created(database, event)
    database[:prs_created] ||= 0
    database[:prs_created] += 1
  end
end

last_event_date = ""
database = {}
processor = Processor.new
events_by_last_updated.each do |event|
  event_date = event["TS"].strftime("%F")
  if event_date != last_event_date
    processor.record_day(database, last_event_date)
    last_event_date = event_date
  end

  puts "#{event["TS"]}: #{event["event"]}"
  case event["event"]
  when "pr_created"
    processor.do_pr_created(database, event)
  end
end
processor.record_day(database, last_event_date)

puts JSON.pretty_generate(database)

#endregion
