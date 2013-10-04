require 'rubygems'
require 'net/ssh'
require 'erb'

##
# Used for generating haproxy configuration with erb.

class HAProxyConfigurationContext

  def initialize(pool_servers, http_pools, tcp_pools)
    @pool_servers, @http_pools, @tcp_pools = pool_servers, http_pools, tcp_pools
  end

  def get_bindings; binding; end

end

##
# Container for bootstrapping a VM. Has things like flavor, image, OpenStack connection, general "pool data", etc.
# Most components should subclass this class and customize their settings accordingly.

class ServerComponent

  [:SSHKeyError, :DuplicateServerNameError, :PEMFileError, :ImageNameError,
    :GitURLError, :SecurityGroupsError, :FlavorNameError, :ServerActivationError].each do |error_class_name|
    const_set(error_class_name, Class.new(StandardError))
  end

  attr_reader :server_name, :server, :ssh_key_name, :pem_file, :image, :flavor, :os_connector, :pool_data

  ##
  # Set up the bare minimum state, e.g. ssh key, pem file, OpenStack connection, for the other methods to do their job.

  def initialize(server_name, ssh_key_name, pem_file, os_connector, pool_data)
    @server_name, @ssh_key_name, @pem_file = server_name, ssh_key_name, File.expand_path(pem_file)
    @os_connector, @pool_data = os_connector, pool_data
  end

  ##
  # Exactly what it says. Open a connection to OpenStack and get the image and flavor data.

  def initialize_image_and_flavor
    os = @os_connector.get_connection
    puts "Image name = #{image_name}."
    @image = os.images.select {|im| im[:name] == image_name}.first
    raise StandardError, "Could not find image: image name = #{image_name}." if @image.nil?
    @flavor = os.flavors.select {|f| f[:name] == flavor_name}.first
    raise StandardError, "Could not find flavor: flavor name = #{flavor_name}." if @flavor.nil?
  end

  ##
  # pool data components

  def pool_name; @pool_name ||= @pool_data["pool-name"]; end
  def http_pool?; @pool_data["load-balance-ports"].nil?; end
  def image_name; @image_name ||= @pool_data["image-name"]; end
  def load_balance_ports; @load_balance_ports ||= @pool_data["load-balance-ports"]; end
  def bootstrap_urls; @bootstrap_urls ||= @pool_data["bootstrap-urls"]; end
  def security_groups; @security_groups ||= @pool_data["security-groups"]; end
  def flavor_name; @flavor_name ||= @pool_data["flavor-name"]; end

  ##
  # Make sure everything is in place for the bootstrapping process to begin. We can't do much
  # if this raises an exception.

  def validate
    puts "Running validators: server name = #{@server_name}."
    os = @os_connector.get_connection

    key_pair = os.keypairs.select {|key_sym, data| data[:name] == ssh_key_name}.first
    if key_pair.nil?
      raise SSHKeyError, "The ssh key does not exist: keypair name = #{ssh_key_name}."
    end
    if !File.exists?(pem_file)
      raise PEMFileError, ".pem file does not exist at specified location: pem file location = #{pem_file}."
    end
    if image.nil?
      raise ImageNameError, "Specified image does not exist: image name = #{image_name}."
    end
    bootstrap_urls.each do |url|
      if url[0..5] != "git://"
        raise GitURLError, "Bootstrap URL must begin with git://: bootstrap url = #{url}."
      end
    end
    os_security_groups = os.security_groups.select {|s_id, v| security_groups.include?(v[:name])}
    if os_security_groups.length != security_groups.length
      raise SecurityGroupsError, [
        "Security group mismatch: requested group(s) = #{security_groups.join(", ")},",
        "found group(s) = #{os_security_groups.map {|v| v[:name]}.join(", ")}."
      ].join(" ")
    end
    if flavor.nil?
      raise FlavorNameError, "Could not find required flavor: flavor name = #{flavor_name}."
    end
  end

  ##
  # Image and flavor must be initialized. Open a connection to OpenStack and create the server.

  def create_server
    os = @os_connector.get_connection
    os.servers.each do |server_data|
      if server_data[:name] == server_name
        raise DuplicateServerNameError, "Server name already exists: server name = #{server_name}."
      end
    end
    server_options = {
      :name => server_name,
      :imageRef => image[:id],
      :flavorRef => flavor[:id],
      :key_name => ssh_key_name,
      :security_groups => security_groups
    }
    @server = os.create_server(server_options)
  end

  ##
  # This should be called before the load balancer does anything if the provisioning
  # of the server happened in a separate process, e.g. by forking a process.

  def get_server
    os = @os_connector.get_connection
    server_data = os.servers.select {|s| s[:name] == server_name}.first
    @server = os.get_server(server_data[:id])
  end

  ##
  # Instance (server) related stats.

  def ip_address; @ip_address ||= server.addresses[0].address; end
  def server_active?; server_status == "ACTIVE"; end
  def server_status; server.refresh; server.status; end

  ##
  # SSH related matters

  def test_ssh_connection
    Net::SSH.start(ip_address, "root", {
      :keys_only => true, :keys => [pem_file],
      :paranoid => false, :verbose => :error
    })
  end

  ##
  # Any ssh command will need to have this prefix because passwordless ssh requires the pem file.

  def ssh_prefix
    @ssh_prefix ||= [
      "ssh -i #{pem_file}",
      "-o UserKnownHostsFile=/dev/null",
      "-o StrictHostKeyChecking=no",
      "root@#{ip_address} -t"
    ].join(" ")
  end

  ##
  # Stick the prefix in front, dump the command to the screen for logging.

  def generate_ssh_command(command)
    command = "#{ssh_prefix} '#{command}'"; puts "command: #{command}"; command
  end

  ##
  # Pre-generate all the commands so that we can debug.

  def generate_commands
    preamble_commands = [
      "apt-get update > /dev/null", "apt-get update > /dev/null", "apt-get -y install git > git_install"
    ]
    bootstrap_commands = bootstrap_urls.each_with_index.map do |git_url, index|
      ["git clone #{git_url} bootstrap-#{index}", "cd bootstrap-#{index} && bash -l bootstrap.sh"]
    end.flatten
    # attach the prefix and return the commands ready to be executed
    all_commands = (preamble_commands + bootstrap_commands).map {|c| "#{ssh_prefix} '#{c}'"}
    # add any non-standard commands like scp and other things
    all_commands << [
      "scp -r -i #{pem_file}",
      "-o UserKnownHostsFile=/dev/null",
      "-o StrictHostKeyChecking=no",
      "public_ssh_keys root@#{ip_address}:"
    ].join(" ")
    all_commands << "#{ssh_prefix} 'cd public_ssh_keys && bash -l pub_key_adder.sh'"
    # log the commands so that we can re-run things and see what went wrong
    all_commands.each {|command| puts "command: #{command}"}
    # return the commands
    all_commands
  end

  ##
  # Validate, create server, generate commands and run them.

  def provision_and_bootstrap
    initialize_image_and_flavor; validate; create_server
    active_check_counter, ssh_test_counter, refresh_delay = 0, 0, 30
    while !server_active?
      if active_check_counter > 5
        raise ServerActivationError, "Server did not become active: server name = #{server_name}."
      else
        active_check_counter += 1; sleep refresh_delay
      end
    end
    begin
      test_ssh_connection
    rescue Exception => e
      if ssh_test_counter > 5
        raise StandardError, "SSH connection failed: server name = #{server_name}."
      else
        ssh_test_counter += 1; sleep refresh_delay; retry
      end
    end
    generate_commands.map {|c| puts "Running command #{c}."; system(c)}
  end

end

##
# A load balancer is just another server component but with some extra commands.
# Currently it depends on successful provisioning of all the pools. TODO: Make this more robust so that it doesn't
# depend on all the pools being successfully provisioned and bootstrapped.

class HAProxyLoadBalancerComponent < ServerComponent

  # sequence of actions should be: 
  # 1) provision and bootstrap pools,
  # 2) provision and bootstrap lb, 
  # 3) generate and upload config,
  # 4) generate and upload /etc/hosts entries
  # in theory the only important part is generating and uploading the config to a functioning load balancer
  # so if any of the previous steps fail then there should be recovery mechanisms in place.
  
  ##
  # Takes http and tcp components and transforms them into a format that can be used
  # by the template to generate 'haproxy.cfg'. This needs to be cleanner because the separation
  # between tcp and http pools is done implicitly by looking at what ports the pool wants to expose.

  def generate_config(http_components, tcp_components, erb_template_string)
    pool_server_mapping = Hash.new {|h, k| h[k] = []}
    http_components_partition = http_components.group_by {|p| p.pool_name}
    tcp_components_partition = tcp_components.group_by {|p| p.pool_name}
    http_pools = http_components_partition.keys
    tcp_pools = tcp_components_partition.map do |k, v|
      {'pool-name' => k, 'load-balance-ports' => v.first.load_balance_ports.value.map(&:value)}
    end
    (http_components + tcp_components).each do |component|
      pool_server_mapping[component.pool_name] << [component.server_name, component.ip_address]
    end
    context = HAProxyConfigurationContext.new(pool_server_mapping,
     http_pools, tcp_pools)
    template = ERB.new(erb_template_string, nil, '>')
    template.result(context.get_bindings)
  end

  ##
  # Upload the configuration to each of the components. TODO: This also needs to happen for box components.

  def upload_config(http_components, tcp_components, erb_template_string)
    # write it to a file and then scp it over
    open('haproxy.cfg', 'w') {|f| f.puts generate_config(http_components, tcp_components, erb_template_string)}
    scp_command = [
      "scp -i #{pem_file}",
      "-o UserKnownHostsFile=/dev/null",
      "-o StrictHostKeyChecking=no",
      "haproxy.cfg root@#{ip_address}:/etc/haproxy"
    ].join(" ")
    puts "Copying haproxy configuration to #{ip_address}."; system(scp_command)
    puts "Restarting haproxy for configuration changes to take effect."
    system(generate_ssh_command("service haproxy restart"))
  end

  ##
  # Generate the 'vip' entries for /etc/hosts by following the pool naming convention.

  def etc_hosts_entries(all_components)
    @etc_hosts_entries ||= all_components.group_by {|c| c.pool_name}.keys.map do |pool_name|
      "#{ip_address} #{pool_name}.vip"
    end
  end

  ##
  # Upload /etc/hosts entries to all the components.

  def upload_etc_hosts_entries(all_components)
    puts "Appending .vip entries to /etc/hosts."
    host_entries = etc_hosts_entries(all_components)
    all_components.each do |server_component|
      host_entries.each do |entry|
        command = server_component.generate_ssh_command("echo #{entry} >> /etc/hosts")
        puts "#{command}"; system(command)
      end
    end
  end

end
