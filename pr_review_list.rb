#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require_relative 'octokit_utils'
require_relative 'options'

options = parse_options

parsed = load_url(options)

util = OctokitUtils.new(options[:oauth])

open_prs = []

def does_array_have_pr(array, pr_number)
  found = false
  array.each do |entry|
    found = true if pr_number == entry.number
  end
  found
end

parsed.each do |_k, v|
  limit = util.client.rate_limit!
  puts "Getting data from Github API for #{v['github']}"
  if limit.remaining == 0
    #  sleep 60 #Sleep between requests to prevent Github API - 403 response
    sleep limit.resets_in
    puts 'Waiting for rate limit reset in Github API'
  end
  sleep 2 # Keep Github API happy
  pr_information_cache = util.fetch_async((v['github']).to_s)
  # no comment from a puppet employee
  puppet_uncommented_pulls = util.fetch_pull_requests_with_no_puppet_personnel_comments(pr_information_cache)
  # last comment mentions a puppet person
  mentioned_pulls = util.fetch_pull_requests_mention_member(pr_information_cache)

  # loop through open pr's and create a row that has all the pertinant info
  pr_information_cache.each do |pr|
    sleep(2)
      if pr[:pull][:draft] == false
        row = {}
        row[:repo] = v['title']
        row[:address] = "https://github.com/#{v['github']}"
        row[:pr] = pr[:pull].number
        row[:age] = ((Time.now - pr[:pull].created_at) / 60 / 60 / 24).round
        row[:owner] = pr[:pull].user.login
        row[:owner] += " <span class='label label-primary'>iac</span>" if util.iac_member?(pr[:pull].user.login)
        row[:owner] += " <span class='label label-warning'>puppet</span>" if util.puppet_member?(pr[:pull].user.login)
        row[:owner] += " <span class='badge badge-secondary'>vox</span>" if util.voxpupuli_member?(pr[:pull].user.login)
        row[:title] = pr[:pull].title

        if !pr[:issue_comments].empty?

          if pr[:issue_comments].last.user.login =~ /\Acodecov/
            begin
              row[:last_comment] = pr[:issue_comments].body(-2).gsub(%r{<\/?[^>]*>}, '')
            rescue StandardError
              row[:last_comment] = 'No previous comment other than codecov-io'
              row[:by] = ''
            end

          else
            row[:last_comment] = pr[:issue_comments].last.body.gsub(%r{<\/?[^>]*>}, '')
            row[:by] = pr[:issue_comments].last.user.login

          end
          row[:age_comment] = ((Time.now - pr[:issue_comments].last.updated_at) / 60 / 60 / 24).round
        else
          row[:last_comment] = '0 comments'
          row[:by] = ''
          row[:age_comment] = 0
        end
        row[:num_comments] = pr[:issue_comments].size

        # find prs not commented by puppet
        row[:no_comment_from_puppet] = does_array_have_pr(puppet_uncommented_pulls, pr[:pull].number)
        # last comment mentions puppet member
        row[:last_comment_mentions_puppet] = does_array_have_pr(mentioned_pulls, pr[:pull].number)

        open_prs.push(row)
      end
  end
end

copy_open_prs = []
copy_open_prs = open_prs

open_prs = copy_open_prs.select { |row| row[:age_comment] > 60 && row[:age_comment] < 90 }
html60 = ERB.new(File.read('pr_review_list.html.erb')).result(binding)
File.open('report60.html', 'wb') do |f|
  f.puts(html60)
end

open_prs = copy_open_prs.select { |row| row[:age_comment] > 30 && row[:age_comment] < 60 }
html30 = ERB.new(File.read('pr_review_list.html.erb')).result(binding)
File.open('report30.html', 'wb') do |f|
  f.puts(html30)
end

open_prs = copy_open_prs.select { |row| row[:age_comment] > 90 }
html90 = ERB.new(File.read('pr_review_list.html.erb')).result(binding)
File.open('report90.html', 'wb') do |f|
  f.puts(html90)
end

open_prs = copy_open_prs
html = ERB.new(File.read('pr_review_list.html.erb')).result(binding)

File.open('report.html', 'wb') do |f|
  f.puts(html)
end

File.open('report.json', 'wb') do |f|
  JSON.dump(open_prs, f)
end
