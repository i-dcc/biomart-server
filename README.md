Biomart Server
==============

This is a straight CVS checkout of the 0.7 branch of [biomart](http://www.biomart.org), with some small modifications 
made for the projects within the [I-DCC](http://www.i-dcc.org).

Mods:

* Modified CSS stylesheet and templates
* Oracle database connections are case-insensitive
* Inclusion of the 'server.rb' script

The server.rb script is a simple helper function to start/stop and reconfigure a biomart 
instance.  This setup is intended to work together with a separate config such as the one 
in the [unitrap-mart](http://github.com/i-dcc/unitrap-mart) repo.
