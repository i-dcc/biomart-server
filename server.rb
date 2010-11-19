#!/usr/bin/env ruby -wKU

# Author::    Darren Oakley  (mailto:do2@sanger.ac.uk)
# Copyright:: Copyright (c) 2009 Darren Oakley
# 
# == Synopsis
# 
# This script is used to stop/start and reconfigure one of our 
# biomart instances.
# 
# == Usage
# 
# ruby server.rb [OPTIONS]
# 
# === Options
# 
# --help:
#   Show help.
#
# --stop:
#   Stop the server.
#
# --start:
#   Start the server.
#
# --production:
#   Use 'production' environments (default is 'test').
#
# --reconfigure:
#   Reconfigure the server (default is just to restart).
#
# --switch_conf:
#   Switch the confguration between the '_mart' and '_mart_alt' 
#   databases. The script will first figure out what the current 
#   server is using and then switch to the opposite configuration.
#

require "getoptlong"
require "rdoc/usage"
require "time"
require "socket"
require "erb"
require "yaml"

##
## Set the script options
##

opts = GetoptLong.new(
  [ '--help',         GetoptLong::NO_ARGUMENT ],
  [ '--stop',         GetoptLong::NO_ARGUMENT ],
  [ '--start',        GetoptLong::NO_ARGUMENT ],
  [ '--production',   GetoptLong::NO_ARGUMENT ],
  [ '--reconfigure',  GetoptLong::NO_ARGUMENT ],
  [ '--switch_conf',  GetoptLong::NO_ARGUMENT ]
)

@@stop        = false
@@start       = false
@@environment = 'test'
@@reconfigure = false
@@switch_conf = false

opts.each do |opt, arg|
  case opt
    when '--help'
      RDoc::usage
    when '--stop'
      @@stop = true
    when '--start'
      @@start = true
    when '--production'
      @@environment = 'production'
    when '--reconfigure'
      @@reconfigure = true
    when '--switch_conf'
      @@switch_conf = true
  end
end

##
## Check for arguments and environment variables
##

# Error class thrown when no APACHECTL environment variable is set.
class ApachectlError < StandardError; end;

##
## Methods
##

def stop_start_server(cmd)
  host = Socket.gethostname
  system("#{MART_CONFIG['apachectl']} -d '#{Dir.pwd}' -f '#{Dir.pwd}/conf/httpd.conf' -k #{cmd}")

  if cmd == "start"
    puts "Biomart is now available at http://#{host}.internal.sanger.ac.uk:#{MART_CONFIG['port']}/biomart"
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
MART_CONFIG = YAML.load_file("../rebuild/settings.yml")[@@environment]
DB_CONFIG   = MART_CONFIG['databases']
CURRENT_DB  = YAML.load_file("../rebuild/current_db.yml")

@@db_to_use = CURRENT_DB[@@environment].clone

# Do we need to switch conf?
if @@switch_conf
  if @@db_to_use == 'standard'
    @@db_to_use = 'alt'
  else
    @@db_to_use = 'standard'
  end
end

# Stop the server
if @@stop
  stop_start_server('stop')
end

# Rebuild the config/template files
build_template( "../rebuild/templates/settings.conf.erb",      "conf/settings.conf" )
build_template( "../rebuild/templates/martDBLocation.xml.erb", "conf/martDBLocation.xml" )
build_template( "../rebuild/templates/log4perl.conf.erb",      "conf/log4perl.conf" )
build_template( "../rebuild/templates/footer.tt.erb",          "conf/templates/custom/footer.tt" )
build_template( "../rebuild/templates/header.tt.erb",          "conf/templates/custom/header.tt" )
build_template( "../rebuild/templates/main.tt.erb",            "conf/templates/custom/main.tt" )

# Reconfigure the biomart
if @@reconfigure
  system("/usr/bin/env perl '#{Dir.pwd}/bin/configure.pl' --clean --recompile -r '#{Dir.pwd}/conf/martDBLocation.xml'")
end

# Restart the biomart
if @@start
  stop_start_server('start')
end

# Finally, re-write the current_db.yml file...
db_conf = CURRENT_DB

if @@switch_conf
  if db_conf[@@environment] == 'standard'
    db_conf[@@environment] = 'alt'
  else
    db_conf[@@environment] = 'standard'
  end
end

file = File.open( "../rebuild/current_db.yml", "w" )
YAML.dump( db_conf, file )
file.close
