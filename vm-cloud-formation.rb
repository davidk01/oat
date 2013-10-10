['rubygems', 'bundler/setup', 'trollop'].each do |req|
  require req
end
['./lib/openstackconnection', './lib/compilers/boxservers',
 './lib/compilers/poolservers', './lib/compilers/haproxy'].each do |req|
  require File.expand_path(req, File.dirname(__FILE__))
end

# output everything to STDERR
def err_puts(string)
  STDERR.puts string
end

# argument parsing
$opts = Trollop::options do
  opt :formation_description, "The file that describes the pools/boxes we want to provision.",
    :type => :string, :required => true
end

err_puts "All operations are going to be performed on '#{ENV['OS_TENANT_NAME']}'."
err_puts "Loading cloud formation file."
cloud_formation_config = File.read($opts[:formation_description])

components = PoolServersCompiler.new(cloud_formation_config, OpenStackConnection.new(ENV))
lb_component = HAProxyCompiler.new(cloud_formation_config, OpenStackConnection.new(ENV))
box_components = BoxServersCompiler.new(cloud_formation_config, OpenStackConnection.new(ENV))
all_server_components = components.all_components + [lb_component.load_balancer] + box_components.boxes

# have to be careful with the ordering
# 1) provision
# 2) provision and bootstrap haproxy
# 3) upload /etc/hosts entries
# 4) bootstrap provisioned boxes

err_puts "Running validators and forking provisioning processes."
all_server_components.map do |component|
  fork {
    server_name = component.server_name
    $stdout.reopen("#{server_name}.out", "a")
    $stderr.reopen("#{server_name}.err", "a")
    component.provision
    puts "#{server_name} provisioned."
  }
end.each {|pid| Process.wait pid}

err_puts "Completing load balancer configuration."
lb_component.load_balancer.bootstrap
# populate server data because we forked and the parent can't see that data
non_error_components = all_server_components.each do |c|
  begin
    c.get_server
  rescue
    err_puts "Something went wrong with #{c.server_name}. Check the logs."
  end
end
# finish the LB configuration
lb_component.load_balancer.upload_config(components.generate_haproxy_config)
err_puts "Appending .vip entries to /etc/hosts in forked processes."
lb_component.load_balancer.upload_etc_hosts_entries(components.all_components + box_components.boxes, components.pool_mappings.keys)

# start the bootstrapping processes for all the boxes
err_puts "Starting bootstrapping processes."
(components.all_components + box_components.boxes).map do |component|
  fork {
    server_name = component.server_name
    $stdout.reopen("#{server_name}.out", "a")
    $stderr.reopen("#{server_name}.err", "a")
    component.bootstrap
    puts "#{server_name} bootstrapped."
  }
end.each {|pid| Process.wait pid}

err_puts "Done!"
