require 'optparse'
require_relative 'octokit_utils'
require 'net/http'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: stats.rb [options]'
  opts.on('-u MANDATORY', '--url=MANDATORY', String, 'Link to json file for modules/tools') { |v| options[:url] = v }
  opts.on('-d','--date DATE','Check from date') { |v| options[:date] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
end

parser.parse!

options[:url] = 'https://puppetlabs.github.io/iac/modules.json' if options[:url].nil?
options[:date] = '31-05-2020' if options[:date].nil?
missing = []
missing << '-t' if options[:oauth].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

util = OctokitUtils.new(options[:oauth])
date_limit = options[:date]

open_prs = []
uri = URI.parse(options[:url])
response = Net::HTTP.get_response(uri)
output = response.body.gsub(/\n/, '')
output.gsub!(/output\".+?(?=previous)/, '')
parsed = JSON.parse(output)

result = {}

def allow_row(row, util)
  dependency_pr = row[:pull].labels.select { |label| label.name.include?"dependencies" }.size
  if util.trusted_contributor?(row[:pull].user.login) or dependency_pr > 0
    return true
  end
  return false
end

parsed.each do |_k, v|
  limit = util.client.rate_limit!
  puts "Getting PR data from Github for #{v['github']}"
  if limit.remaining == 0
    #  sleep 60 #Sleep between requests to prevent Github API - 403 response
    sleep limit.resets_in
    puts 'Waiting for rate limit reset in Github API'
  end
  sleep 2 # Keep Github API happy
  pr_information_cache = util.fetch_async((v['github']).to_s, 
                                          options = { state: 'closed', sort: 'updated'},
                                          filter = %i[statuses pull_request_commits issue_comments],
                                          limit = { attribute: 'closed_at', date: Date.parse(date_limit) }
                                         )
  result[v['github']] = pr_information_cache.select { |row| allow_row(row, util) }.size
end

puts "Repository, Trusted Contributor Activity PRs since #{date_limit}"
result.each do |k,v|
  puts "#{k},#{v}"
end
