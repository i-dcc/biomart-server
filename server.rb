#!/usr/bin/env ruby
# encoding: utf-8

## 
## This script is used to stop/start and reconfigure one of our 
## biomart instances.
## 

require 'optparse'
require 'time'
require 'socket'
require 'erb'
require 'yaml'

##
## Check for arguments and environment variables
##

@options = {
  :start        => false,
  :stop         => false,
  :reconfigure  => false,
  :switch_conf  => false,
  :environment  => nil,
  :rebuilddir   => '../rebuild',
  :service_user => nil
}

OptionParser.new do |opts|
  opts.banner = 'Usage: server.rb [options]'
  opts.on('--start', 'Start the biomart server')                                      { |arg| @options[:start] = arg }
  opts.on('--stop', 'Stop the biomart server')                                        { |arg| @options[:stop] = arg }
  opts.on('--reconfigure', '-r', 'Reconfigure the biomart server')                    { |arg| @options[:reconfigure] = arg }
  opts.on('--switch_conf', '-s', 'Make the biomart server switch databases')          { |arg| @options[:switch_conf] = arg }
  opts.on('--environment [ENV]', '-e', String, 'Environment config to use')           { |arg| @options[:environment] = arg }
  opts.on('--rebuilddir [DIR]', 'Rebuild directory')                                  { |arg| @options[:rebuilddir] = arg }
  opts.on('--service_user [USER]', String, 'User that runs the biomart server - if not current user') { |arg| @options[:service_user] = arg }
end.parse!

raise ArgumentError, 'You must specify an --environment option!' if @options[:environment].nil?

MART_CONFIG = YAML.load_file("#{@options[:rebuilddir]}/settings.yml")[@options[:environment]]

raise ArgumentError, "We can't find an environment config '#{@options[:environment]}'!" if MART_CONFIG.nil?

DB_CONFIG         = MART_CONFIG['databases']
CURRENT_DB        = YAML.load_file("#{@options[:rebuilddir]}/current_db.yml")
REBUILD_TIMESTAMP = YAML.load_file("#{@options[:rebuilddir]}/rebuild_timestamp.yml")

# Error class thrown when no APACHECTL environment variable is set.
class ApachectlError < StandardError; end;

##
## Methods
##

def stop_start_server( cmd, user=nil )
  host    = Socket.gethostname
  command = "#{MART_CONFIG['apachectl']} -d '#{Dir.pwd}' -f '#{Dir.pwd}/conf/httpd.conf' -k #{cmd}"
  command = "sudo -u #{user} #{command}" unless user.nil?
  system(command)
  
  if cmd == "start"
    puts "Biomart is now available at http://#{host}:#{MART_CONFIG['port']}/biomart"
  else
    puts "Biomart has been stopped"
  end
end

def build_template( template_file, output_file )
  if File.exists?( template_file )
    template = File.open( template_file, 'r' )
    erb = ERB.new( template.read )
    output = File.open( output_file, 'w' )
    output.write( erb.result( binding ) )
    output.close
  end
end

##
## Main body of script
##

# First, read in our settings file

@db_to_use = CURRENT_DB[@options[:environment]].clone

# Do we need to switch conf?
if @options[:switch_conf]
  if @db_to_use == 'standard'
    @db_to_use = 'alt'
  else
    @db_to_use = 'standard'
  end
end

# Stop the server
stop_start_server( 'stop', @options[:service_user] ) if @options[:stop]

# Rebuild the config/template files
build_template( "#{@options[:rebuilddir]}/templates/settings.conf.erb",      "conf/settings.conf" )
build_template( "#{@options[:rebuilddir]}/templates/martDBLocation.xml.erb", "conf/martDBLocation.xml" )
build_template( "#{@options[:rebuilddir]}/templates/log4perl.conf.erb",      "conf/log4perl.conf" )
build_template( "#{@options[:rebuilddir]}/templates/footer.tt.erb",          "conf/templates/custom/footer.tt" )
build_template( "#{@options[:rebuilddir]}/templates/header.tt.erb",          "conf/templates/custom/header.tt" )
build_template( "#{@options[:rebuilddir]}/templates/main.tt.erb",            "conf/templates/custom/main.tt" )

# Reconfigure the biomart
if @options[:reconfigure]
  system("/usr/bin/env perl '#{Dir.pwd}/bin/configure.pl' --clean --recompile -r '#{Dir.pwd}/conf/martDBLocation.xml'")
end

# Restart the biomart
stop_start_server( 'start', @options[:service_user] ) if @options[:start]

# Finally, re-write the current_db.yml file...
db_conf = CURRENT_DB

if @options[:switch_conf]
  if db_conf[@options[:environment]] == 'standard'
    db_conf[@options[:environment]] = 'alt'
  else
    db_conf[@options[:environment]] = 'standard'
  end
end

file = File.open( "#{@options[:rebuilddir]}/current_db.yml", "w" )
YAML.dump( db_conf, file )
file.close
