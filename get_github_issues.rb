require 'optparse'
require_relative 'octokit_utils'
require 'net/http'

options = {}
options[:oauth] = ENV['GITHUB_COMMUNITY_TOKEN'] if ENV['GITHUB_COMMUNITY_TOKEN']
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: get_github_issues.rb [options]'
  opts.on('-u MANDATORY', '--url=MANDATORY', String, 'Link to json file for tools') { |v| options[:url] = v }
  opts.on('-d','--date DATE','Check from date') { |v| options[:date] = v }
  opts.on('-t', '--oauth-token TOKEN', 'OAuth token. Required.') { |v| options[:oauth] = v }
end

parser.parse!

options[:url] = 'https://puppetlabs.github.io/iac/modules.json' if options[:url].nil?
options[:date] = '31-12-2020' if options[:date].nil?
missing = []
missing << '-t' if options[:oauth].nil?
unless missing.empty?
  puts "Missing options: #{missing.join(', ')}"
  puts parser
  exit
end

util = OctokitUtils.new(options[:oauth])
date_limit = Date.parse(options[:date])

uri = URI.parse(options[:url])
response = Net::HTTP.get_response(uri)
output = response.body.gsub(/\n/, '')
parsed = JSON.parse(output)

issuehash = {}

parsed.each do |k,v|
  limit = util.client.rate_limit!
  puts "Getting issue data from Github for #{v['github']}"
  if limit.remaining == 0
    #  sleep 60 #Sleep between requests to prevent Github API - 403 response
    sleep limit.resets_in
    puts 'Waiting for rate limit reset in Github API'
  end
  sleep 2 # Keep Github API happy
  issuehash[v['github']] = []
  total_events = util.client.repository_issue_events((v['github']).to_s)
  total_events.each do |event|
    if event[:issue][:updated_at].utc > date_limit.to_time.utc && event[:issue][:html_url].include?('issue')
      if util.iac_member?(event[:actor][:login])
        issuehash[v['github']] << event[:issue]
      end
    end
  end
  rescue StandardError => e
  puts "No issues for this module: #{e}"
end

puts "Hash of issues"
issuehash.each do |k,v|
  puts "Module #{k}"
  v.each do |issue|
    puts "#{issue[:number]} | #{issue[:event]} | #{issue[:updated_at]} | #{issue[:html_url]}"
  end
end

puts '-'*100

counter = 1
puts "Unique issues addressed in each module"
issuehash.each do |k,v|
  puts "Module #{k}"
  uniqueissues = v.uniq { |x| x[:number] }
  uniqueissues.each do |issue|
    counter += 1
    puts "#{issue[:number]} - #{issue[:html_url]}"
  end
end

puts "Total issues addressed by the IAC team: #{counter}"
