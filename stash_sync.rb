#!/usr/bin/env ruby

# Script modified from http://dev.bizo.com/2011/05/synchronizing-stashboard-with-pingdom.html
require 'rubygems'
require 'time'
require 'date'
require 'logger'
require 'pingdom-client'
require 'active_support/core_ext/numeric/time' # time extensions, e.g., 5.days
require 'stashboard'

TIME_FORMAT = "%Y-%m-%d %H:%M:%S %Z" # YYYY-MM-DD HH:MM:SS ZZZ
logger = Logger.new(STDOUT)
logger.level = Logger::WARN

pingdom_auth = {
  :username => ENV['PINGDOM_IMAGO_USER'],
  :password => ENV['PINGDOM_IMAGO_PASS'],
  :key => ENV['PINGDOM_IMAGO_KEY']
}

stashboard_auth = {
  :url          => ENV['STASHBOARD_URL'],
  :oauth_token  => ENV['STASHBOARD_TOKEN'],
  :oauth_secret => ENV['STASHBOARD_SECRET']
}

# Stashboard service id => Regex matching pingdom check name(s)
services = {
  'imago'    => /imago/i
}

stashboard = Stashboard::Stashboard.new(
  stashboard_auth[:url],
  stashboard_auth[:oauth_token],
  stashboard_auth[:oauth_secret]
)

pingdom = Pingdom::Client.new pingdom_auth.merge(:logger => logger)

stashboard.service_ids.each do |service|
  puts "WARNING:  Missing mapping for stashboard service '#{service}'" unless services[service]
end

# Synchronize recent pingdom outages over to stashboard and determine which services
# are currently up.
pingdom.checks.each do |check|

  service = services.keys.find do |service|
    regex = services[service]
    check.name =~ regex
  end

  unless service
    next
  end

  puts "Check: #{check.name} => #{check.status} [#{service}]"
  
  # Find outages in the last 6 hrs
  yesterday = Time.now - 6.hours
  recent_outages = check.summary.outages.select do |outage|
    Time.at(outage.timefrom.to_i).to_datetime > yesterday || Time.at(outage.timeto.to_i).to_datetime > yesterday
  end

  if check.status == "down"
    # Service is down. Update status no matter what
    puts "Service currently unavailable."
    stashboard.create_event(service, "down", "Service currently unavailable.")
  elsif !recent_outages.empty?
    # Service has been down in last 24 hrs
    current = stashboard.current_event(service)
    # Only update status if status is not custom or self was last status
    if current["message"] =~ /(Service .* unavailable)|(Service operating normally)/i
      puts "Service experienced outages in past 24 hours: #{service}"
      stashboard.create_event(service, "warning", "Service operational but has experienced outage(s) in past 6 hours.")
    end
  else
    # Service is Up!
    current = stashboard.current_event(service)
    # Only update status if status is not custom or self was last status
    if current["message"] =~ /(Service .* unavailable)|(Service operational but has experienced outage)/i
      puts "Service now operating normally: #{service}"
      stashboard.create_event(service, "up", "Service operating normally.")
    end
  end
end