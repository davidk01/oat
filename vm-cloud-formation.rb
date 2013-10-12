['rubygems', 'bundler/setup', 'trollop'].each do |req|
  require req
end
['./lib/openstackconnection', './lib/compilers/boxservers',
 './lib/compilers/poolservers', './lib/compilers/haproxy'].each do |req|
  require File.expand_path(req, File.dirname(__FILE__))
end

old_stdout = $stdout.dup
$stdout.reopen($stderr)

# argument parsing
$opts = Trollop::options do
  opt :formation_description, "The file that describes the pools/boxes we want to provision.",
    :type => :string, :required => true
end

puts "All operations are going to be performed on '#{ENV['OS_TENANT_NAME']}'."
puts "Loading cloud formation file."
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

puts "Running validators and forking provisioning processes."
all_server_components.map do |component|
  fork {
    server_name = component.server_name
    $stdout.reopen("#{server_name}.out", "a")
    $stderr.reopen("#{server_name}.err", "a")
    component.provision
    puts "#{server_name} provisioned."
  }
end.each {|pid| Process.wait pid}

puts "Making sure all components were provisioned by OpenStratus (OpenStack) and testing ssh connection status."
all_server_components.each do |c|
  begin
    c.get_server; c.test_ssh_connection
  rescue
    puts "Something went wrong with #{c.server_name}. Check the logs and re-run vm-cloud-formation."
    exit 1
  end
end

puts "Completing load balancer configuration."
lb_component.load_balancer.bootstrap
# finish the LB configuration
lb_component.load_balancer.upload_config(components.generate_haproxy_config)
puts "Appending .vip entries to /etc/hosts in forked processes."
lb_component.load_balancer.upload_etc_hosts_entries(components.all_components + box_components.boxes, components.pool_mappings.keys)

# start the bootstrapping processes for all the boxes
puts "Starting bootstrapping processes and waiting for them to finish. Check the logs for progress."
(components.all_components + box_components.boxes).map do |component|
  fork {
    server_name = component.server_name
    $stdout.reopen("#{server_name}.out", "a")
    $stderr.reopen("#{server_name}.err", "a")
    component.bootstrap
    puts "#{server_name} bootstrapped."
  }
end.each {|pid| Process.wait pid}
puts "Done!"
