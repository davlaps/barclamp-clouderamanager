#
# Cookbook Name: clouderamanager
# Recipe: cm-server.rb
#
# Copyright (c) 2011 Dell Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'clouderamanager::cm-common'

#######################################################################
# Begin recipe
#######################################################################
debug = node[:clouderamanager][:debug]
Chef::Log.info("CM - BEGIN clouderamanager:cm-server") if debug

# Configuration filter for our crowbar environment.
env_filter = " AND environment:#{node[:clouderamanager][:config][:environment]}"

# Install the Cloudera Manager server packages.
pkg_list=%w{
    cloudera-manager-daemons
    cloudera-manager-server-db
    cloudera-manager-server
  }

pkg_list.each do |pkg|
  package pkg do
    action :install
  end
end

# Cloudera Manager needs to have this directory present. Without it,
# the slave node installation will fail. This is an empty directory and the
# RPM package installer does not seem to create it.
directory "/usr/share/cmf/packages" do
  owner "root"
  group "root"
  mode "0755"
  action :create
end

# Define the Cloudera Manager server service.
# cloudera-scm-server {start|stop|restart|status}
service "cloudera-scm-server" do
  supports :start => true, :stop => true, :restart => true, :status => true 
  action :enable 
end

# Define the Cloudera Manager database service.
# cloudera-scm-server-db {start|stop|restart|status|initdb}
service "cloudera-scm-server-db" do
  supports :start => true, :stop => true, :restart => true, :status => true 
  action :enable 
end

include_recipe 'clouderamanager::postgresql'

# Setup the postgresql configuration. This is used to store CM
# configuration information.
# This will only run if the db is uninitialized, otherwise it returns 1. 
# /var/lib/cloudera-scm-server-db/data is non-empty; perhaps the database
# was already initialized?
bash "cloudera-scm-server-db" do
  code <<-EOH
/etc/init.d/cloudera-scm-server-db initdb
EOH
  # Should only notify on initial creation only.
  # notifies :restart, resources(:service => "cloudera-scm-server")
  returns [0, 1] 
end

# Start the Cloudera Manager database service.
service "cloudera-scm-server-db" do
  action :start 
end

# Start the Cloudera Manager server service.
service "cloudera-scm-server" do
  action :start 
end

# Find the Cloudera web application node and add the UI link. 
webapp_service_nodes = []
search(:node, "roles:clouderamanager-webapp#{env_filter}") do |obj|
  webapp_service_nodes << obj if obj and obj[:fqdn] and !obj[:fqdn].empty?
end

# Add the cloudera manager link to the crowbar UI.
Chef::Log.info("CM - Found cloudera manager web application {" + webapp_service_nodes[0][:fqdn] + "}") if debug 
if webapp_service_nodes and webapp_service_nodes.length > 0
  obj = webapp_service_nodes[0]
  server_ip = BarclampLibrary::Barclamp::Inventory.get_network_by_type(obj,"public").address
  if server_ip.nil? or server_ip.empty?
    server_ip = BarclampLibrary::Barclamp::Inventory.get_network_by_type(obj,"admin").address
  end  
  node[:crowbar] = {} if node[:crowbar].nil? 
  node[:crowbar][:links] = {} if node[:crowbar][:links].nil?
  if server_ip
    url = "http://#{server_ip}:7180/cmf/login" 
    Chef::Log.info("CM - Cloudera management services URL [#{url}]") if debug 
    node[:crowbar][:links]["Cloudera Manager"] = url 
  else
    node[:crowbar][:links].delete("Cloudera Manager")
  end
else
  node[:crowbar][:links].delete("Cloudera Manager")
end

#######################################################################
# End of recipe
#######################################################################
Chef::Log.info("CM - END clouderamanager:cm-server") if debug
