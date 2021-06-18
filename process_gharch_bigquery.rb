#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'

# -- filter all data into basedata table for cheaper and faster local dev
# CREATE OR REPLACE TABLE gharchive.basedata
# PARTITION BY TIMESTAMP_TRUNC(created_at, month)
# CLUSTER BY repo_name
# AS
#   SELECT type, payload, repo.id as repo_id, repo.name as repo_name, actor.id as actor_id, actor.login as actor_login, org.id as org_id, org.login as org_login, created_at, id, other FROM `githubarchive.month.*`
#   WHERE
#   --   _TABLE_SUFFIX = FORMAT_DATE("%Y%m", DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)) AND
#     _TABLE_SUFFIX BETWEEN '201700' AND '202107' AND
# --     _TABLE_SUFFIX BETWEEN '202106' AND '202107' AND
#     STARTS_WITH(LOWER(repo.name), 'puppetlabs/')
#
# -- select data for a specific repo
# SELECT type, created_at, actor_login, repo_name, payload FROM `iac-tasks.gharchive.basedata` WHERE repo_name = 'puppetlabs/puppetlabs-motd' ORDER BY created_at
MODULE_TIERS = {
  'puppetlabs/cisco_ios' => 'Bronze',
  'puppetlabs/puppetlabs-accounts' => 'Gold',
  'puppetlabs/puppetlabs-acl' => 'Gold',
  'puppetlabs/puppetlabs-apache' => 'Gold',
  'puppetlabs/puppetlabs-apt' => 'Gold',
  'puppetlabs/puppetlabs-chocolatey' => 'Gold',
  'puppetlabs/puppetlabs-concat' => 'Gold',
  'puppetlabs/puppetlabs-docker' => 'Gold',
  'puppetlabs/puppetlabs-firewall' => 'Gold',
  'puppetlabs/puppetlabs-haproxy' => 'Gold',
  'puppetlabs/puppetlabs-kubernetes' => 'Gold',
  'puppetlabs/puppetlabs-mysql' => 'Gold',
  'puppetlabs/puppetlabs-package' => 'Gold',
  'puppetlabs/puppetlabs-postgresql' => 'Gold',
  'puppetlabs/puppetlabs-powershell' => 'Gold',
  'puppetlabs/puppetlabs-reboot' => 'Gold',
  'puppetlabs/puppetlabs-registry' => 'Gold',
  'puppetlabs/puppetlabs-stdlib' => 'Gold',
  'puppetlabs/puppetlabs-tomcat' => 'Gold',
  'puppetlabs/provision' => 'Silver',
  'puppetlabs/puppetlabs-dsc_lite' => 'Silver',
  'puppetlabs/puppetlabs-exec' => 'Silver',
  'puppetlabs/puppetlabs-facter_task' => 'Silver',
  'puppetlabs/puppetlabs-helm' => 'Silver',
  'puppetlabs/puppetlabs-iis' => 'Silver',
  'puppetlabs/puppetlabs-inifile' => 'Silver',
  'puppetlabs/puppetlabs-java' => 'Silver',
  'puppetlabs/puppetlabs-java_ks' => 'Silver',
  'puppetlabs/puppetlabs-motd' => 'Silver',
  'puppetlabs/puppetlabs-ntp' => 'Silver',
  'puppetlabs/puppetlabs-resource_api' => 'Silver',
  'puppetlabs/puppetlabs-rook' => 'Silver',
  'puppetlabs/puppetlabs-scheduled_task' => 'Silver',
  'puppetlabs/puppetlabs-sqlserver' => 'Silver',
  'puppetlabs/puppetlabs-tagmail' => 'Silver',
  'puppetlabs/puppetlabs-vcsrepo' => 'Silver',
  'puppetlabs/device_manager' => 'Bronze',
  'puppetlabs/puppetlabs-dsc' => 'Bronze',
  'puppetlabs/puppetlabs-ibm_installation_manager' => 'Bronze',
  'puppetlabs/puppetlabs-panos' => 'Bronze',
  'puppetlabs/puppetlabs-puppet_conf' => 'Bronze',
  'puppetlabs/puppetlabs-satellite_pe_tools' => 'Bronze',
  'puppetlabs/puppetlabs-service' => 'Bronze',
  'puppetlabs/puppetlabs-vsphere' => 'Bronze',
  'puppetlabs/puppetlabs-websphere_application_server' => 'Bronze',
  'puppetlabs/puppetlabs-wsus_client' => 'Bronze'
}.freeze

GOOGLE_SHEETS_DATE_FORMAT = '%m/%d/%Y %H:%M:%S' # FFS

RE_Q1 = /Q(01|02|03)/.freeze
RE_Q2 = /Q(04|05|06)/.freeze
RE_Q3 = /Q(07|08|09)/.freeze
RE_Q4 = /Q(10|11|12)/.freeze
def quarterize(time)
  time.strftime('%Y-Q%0m').gsub(RE_Q1, 'Q1').gsub(RE_Q2, 'Q2').gsub(RE_Q3, 'Q3').gsub(RE_Q4, 'Q4')
end

BEFORE_TIME = Time.parse('2019-03-07')
PANDEMIC_HIT = Time.parse('2020-03-07')

def in_lockdown?(time)
  if time < BEFORE_TIME
    ''
  elsif time < PANDEMIC_HIT
    'pre-pandemic'
  else
    'pandemic'
  end
end

AFFILIATIONS = Hash.new { |_k| :community }

def affiliate(members, tag)
  members.each { |m| AFFILIATIONS[m] = tag }
end

REPOS = Hash.new { |_k| :unknown }
def repo_tag(repos, tag)
  repos.each { |m| REPOS[m] = tag }
end

BOTS = [
  'CLAassistant',
  'dependabot-preview[bot]',
  'dependabot[bot]',
  'github-actions[bot]',
  'puppet-community-rangefinder[bot]'
].freeze
affiliate(BOTS, :bot)

IAC = %w[
  adrianiurca
  binford2k
  bmjen
  carabasdaniel
  cdanny2411
  clairecadman
  cmccrisken-puppet
  da-ar
  daianamezdrea
  davejrt
  david22swan
  davidmalloncares
  DavidS
  davinhanlon
  Disha-maker
  eimlav
  eputnam
  florindragos
  glennsarti
  gregohardy
  HAIL9000
  HelenCampbell
  hunner
  Iristyle
  jbondpdx
  jpogran
  Lavinia-Dan
  lionce
  MaxMagill
  michaeltlombardi
  pmcmaw
  RandomNoun7
  sanfrancrisko
  scotje
  scotty-c
  sheenaajay
  shermdog
  Thomas-Franklin
  ThoughtCrhyme
  tphoney
  willmeek
  wilson208
].freeze
affiliate(IAC, :iac)

PUPPET = %w[
  abottchen
  abuxton
  adreyer
  beechtom
  conormurraypuppet
  cthorn42
  daniel5119
  donoghuc
  dylanratcliffe
  EamonnTP
  ferventcoder
  gabe-sky
  GabrielNagy
  genebean
  gimmyxd
  hlindberg
  IrimieBogdan
  james-stocks
  jarretlavallee
  jonnytdevops
  lucywyman
  MartyEwings
  mihaibuzgau
  MikaelSmith
  MWilsonPuppet
  Nekototori
  nmaludy
  npwalker
  reidmv
  rodjek
  sarameisburger
  sbeaulie
  Sharpie
  spynappels
  tkishel
  WhatsARanjit
].freeze
affiliate(PUPPET, :puppet)

TCP = %w[
  alexjfisher
  b4ldr
  bastelfreak
  ekohl
  smortex
].freeze
affiliate(TCP, :'puppet-trusted')

MODULE_REPOS = %w[
  puppetlabs/cisco_ios
  puppetlabs/device_manager
  puppetlabs/provision
  puppetlabs/puppetlabs-accounts
  puppetlabs/puppetlabs-acl
  puppetlabs/puppetlabs-apache
  puppetlabs/puppetlabs-apt
  puppetlabs/puppetlabs-chocolatey
  puppetlabs/puppetlabs-concat
  puppetlabs/puppetlabs-docker
  puppetlabs/puppetlabs-dsc_lite
  puppetlabs/puppetlabs-dsc
  puppetlabs/puppetlabs-exec
  puppetlabs/puppetlabs-facter_task
  puppetlabs/puppetlabs-firewall
  puppetlabs/puppetlabs-haproxy
  puppetlabs/puppetlabs-helm
  puppetlabs/puppetlabs-ibm_installation_manager
  puppetlabs/puppetlabs-iis
  puppetlabs/puppetlabs-inifile
  puppetlabs/puppetlabs-java_ks
  puppetlabs/puppetlabs-java
  puppetlabs/puppetlabs-kubernetes
  puppetlabs/puppetlabs-motd
  puppetlabs/puppetlabs-mysql
  puppetlabs/puppetlabs-ntp
  puppetlabs/puppetlabs-package
  puppetlabs/puppetlabs-panos
  puppetlabs/puppetlabs-postgresql
  puppetlabs/puppetlabs-powershell
  puppetlabs/puppetlabs-puppet_conf
  puppetlabs/puppetlabs-reboot
  puppetlabs/puppetlabs-registry
  puppetlabs/puppetlabs-rook
  puppetlabs/puppetlabs-satellite_pe_tools
  puppetlabs/puppetlabs-scheduled_task
  puppetlabs/puppetlabs-service
  puppetlabs/puppetlabs-sqlserver
  puppetlabs/puppetlabs-stdlib
  puppetlabs/puppetlabs-tagmail
  puppetlabs/puppetlabs-testing
  puppetlabs/puppetlabs-tomcat
  puppetlabs/puppetlabs-vcsrepo
  puppetlabs/puppetlabs-vsphere
  puppetlabs/puppetlabs-websphere_application_server
  puppetlabs/puppetlabs-wsus_client
].freeze
repo_tag(MODULE_REPOS, :module)

TOOL_REPOS = %w[
  puppetlabs/action-litmus_parallel
  puppetlabs/action-litmus_spec
  puppetlabs/community_management
  puppetlabs/dependency_checker
  puppetlabs/iac
  puppetlabs/litmus
  puppetlabs/litmusimage
  puppetlabs/puppet_litmus
  puppetlabs/pdk-templates
  puppetlabs/puppet-approved
  puppetlabs/PuppetDscBuilder
  puppetlabs/puppetlabs_spec_helper
  puppetlabs/puppet-modulebuilder
  puppetlabs/puppet-module-gems
  puppetlabs/puppet-strings
  puppetlabs/puppet-resource_api
  puppetlabs/ruby-pwsh
].freeze
repo_tag(TOOL_REPOS, :tool)

# require 'pry'; binding.pry

scratchpad = {}

# puts 'created_at,repo,repo_tag,created_by,affiliation'

puts 'created_at,created_at_quarter,repo,repo_tag,created_by,affiliation,resolved_at,resolved_at_quarter,merged_by,merged_aff,resolution,days_to_resolution,created_in_lockdown,resolved_in_lockdown,tier,labels'
# puts "#{e[:created_at].strftime(GOOGLE_SHEETS_DATE_FORMAT)},#{e[:repo]},#{e[:repo_tag]},#{e[:created_by]},#{e[:affiliation]},#{pr[:resolved_at].strftime(GOOGLE_SHEETS_DATE_FORMAT)},#{pr[:merged_by]},#{pr[:merged_aff]},#{pr[:resolution]},#{e[:days_to_resolution]}"

File.foreach('/home/david/Downloads/bq-results-20210616-112625-m7mpogci3ubf.json') do |line|
  event = JSON.parse(line)
  payload = JSON.parse(event['payload'])

  data = {
    created_at: event['created_at'],
    type: event['type'],
    actor: event['actor_login'],
    actor_affiliation: AFFILIATIONS[event['actor_login']],
    repo: event['repo_name'],
    repo_tag: REPOS[event['repo_name']]
  }
  case event['type']
  when 'CreateEvent', 'DeleteEvent'
    # create new branch
    # payload = {"ref":"hunner_msync","ref_type":"branch","master_branch":"master","description":"Simple motd module ","pusher_type":"user"}

    # delete a branch
    # payload = {"ref":"hunner_msync","ref_type":"branch","pusher_type":"user"}

    next
  when 'ForkEvent', 'IssuesEvent', 'CommitCommentEvent', 'GollumEvent', 'PublicEvent', 'ReleaseEvent'
    data.merge!({})
  when 'PushEvent'
    # update a commit - for example when a PR is merged
    # payload = {"push_id":1488389358,"size":1,"distinct_size":1,"ref":"refs/heads/hunner_msync","head":"2ed198647c78918ff8d8645b20dece410d38c120","before":"bfa4952fad9525a23dbb663ab51cda9e7d9930a1","commits":[{"sha":"2ed198647c78918ff8d8645b20dece410d38c120","author":{"name":"Hunter Haugen","email":"6e6fb81d558ed2e8cc445f2d4379b7e99449d647@puppet.com"},"message":"(MODULES-4097) Sync travis.yml","distinct":true,"url":"https://api.github.com/repos/puppetlabs/puppetlabs-motd/commits/2ed198647c78918ff8d8645b20dece410d38c120"}]}

    data.merge!({})
  when 'IssueCommentEvent'
    data.merge!(
      number: payload['issue']['number'],
      comment: payload['comment']['url']
    )
    # puts "comment by #{data[:actor]}"
  when 'PullRequestEvent'
    data.merge!(
      number: payload['number'],
      action: payload['action'],
      head: payload['pull_request']['head']['sha'],
      base: payload['pull_request']['base']['sha'],
      merged: payload['pull_request']['merged']
    )
    case data[:action]
    when 'opened'
      e = scratchpad["#{data[:repo]}#pr#{data[:number]}"] = {
        created_at: Time.parse(data[:created_at]),
        repo: data[:repo],
        repo_tag: data[:repo_tag],
        created_by: data[:actor],
        affiliation: data[:actor_affiliation]
      }
      # puts "created PR: #{data[:actor]}"
      # require'pry';binding.pry

      # puts scratchpad["pr#{data[:number]}"].values.map(&:to_s).join(',')

      # puts "#{e[:created_at].strftime(GOOGLE_SHEETS_DATE_FORMAT)},#{e[:repo]},#{e[:repo_tag]},#{e[:created_by]},#{e[:affiliation]}"

      # puts e[:created_by] if e[:affiliation] == :community
    when 'closed'
      # skip PRs opened before our data
      pr = scratchpad["#{data[:repo]}#pr#{data[:number]}"]
      next unless pr # skip PRs where we don't see the start

      seconds_to_resolution = Time.parse(data[:created_at]) - pr[:created_at]
      # puts payload['pull_request']['labels'].inspect
      pr.merge!(
        resolved_at: Time.parse(data[:created_at]),
        days_to_resolution: seconds_to_resolution / 60.0 / 60.0 / 24.0,
        merged_by: data[:actor],
        merged_aff: data[:actor_affiliation],
        resolution: data[:merged] ? :merged : :rejected,
        labels: payload['pull_request']['labels']&.map{|l| l['name']}&.sort&.join(" ") || 'none'
      )

      # require'pry';binding.pry

      puts "#{pr[:created_at].strftime(GOOGLE_SHEETS_DATE_FORMAT)},#{quarterize(pr[:created_at])},#{pr[:repo]},#{pr[:repo_tag]},#{pr[:created_by]},#{pr[:affiliation]},#{pr[:resolved_at].strftime(GOOGLE_SHEETS_DATE_FORMAT)},#{quarterize(pr[:resolved_at])},#{pr[:merged_by]},#{pr[:merged_aff]},#{pr[:resolution]},#{pr[:days_to_resolution]},#{in_lockdown?(pr[:created_at])},#{in_lockdown?(pr[:resolved_at])},#{MODULE_TIERS[pr[:repo]] || 'unknown'}"
    end
  when 'PullRequestReviewCommentEvent'
    data.merge!(
      number: payload['pull_request']['number'],
      comment: payload['comment']['url']
    )
    # puts "comment by #{data[:actor]}"
  when 'PullRequestReviewEvent'
    data.merge!(
      number: payload['pull_request']['number'],
      action: payload['review']['state']
    )
    # puts "review by #{data[:actor]}"
  when 'WatchEvent'
    data.merge!({})
  when 'MemberEvent'
    data.merge!(
      action: payload['action'],
      new_member: payload['member']['login']
    )
  else
    puts "#{event['created_at']}, #{event['type']} by #{event['actor_login']}"
    puts event['payload']
    # exit
  end

  # puts JSON.generate(data)
end

# puts "SELECT type, created_at, actor_login, repo_name, payload FROM `iac-tasks.gharchive.basedata` WHERE repo_name in (#{REPOS.keys.sort.uniq.map { |r| "'#{r}'" }.join(',')}) ORDER BY created_at"
