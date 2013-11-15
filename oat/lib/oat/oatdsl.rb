class CloudFormation

  ##
  # Simple struct for holding git URLs.

  class GitUrl < Struct.new(:git_url)
    def git_url?
      git_url[0..5] == 'git://'
    end
  end

  ##
  # We need a way to keep track of service definitions as well so a simple struct
  # will work.

  class ServiceDefinition < Struct.new(:service_port, :healthcheck_endpoint, :healthcheck_port)
    def service?
      true
    end
  end

  ##
  # Do everything with formation block.

  def self.formation(&blk)
    instance = self.new
    (class << instance; self; end).instance_eval do
      define_method(:define_formation, &blk)
    end
    instance.define_formation
    instance
  end

  ##
  # It's better to break up the +run+ method into multiple methods to make dependencies
  # explicit via parameters.

  def provision_servers(all_servers)
    puts "Running validators and forking provisioning processes."
    # make sure the servers are up and running
    all_servers.map do |component|
      fork {
        server_name = component.server_name
        $stdout.reopen("#{server_name}.out", "a")
        $stderr.reopen("#{server_name}.err", "a")
        component.provision
        puts "#{server_name} provisioned."
      }
    end.each {|pid| Process.wait pid}
  end

  ##
  # Another stage in the +run+ method pipeline.

  def test_ssh_connections(all_servers)
    puts "Making sure all components were provisioned by OpenStack."
    all_servers.each do |c|
      begin
        c.get_server; c.test_ssh_connection
      rescue Exception => e
        puts "Something went wrong with #{c.server_name}. Check the logs and re-run vm-cloud-formation."
        puts e
        exit 1
      end
    end
  end

  ##
  # This returns the PID for the process that is configuring the load
  def etc_host_entry_config(pools, boxes, lb)
    puts "Appending .vip entries to /etc/hosts in forked processes."
    pool_names = pools.http_pool_mappings.merge(pools.tcp_pool_mappings).keys
    puts "Pools: #{pool_names.join(", ")}."
    lb.upload_etc_hosts_entries(pools.all_components + boxes, pool_names)
    # load balancer bootstrapping should happen independently of all the other boxes
    lb_bootstrap_pid = fork {
      server_name = lb.server_name
      $stdout.reopen("#{server_name}.out", "a")
      $stderr.reopen("#{server_name}.err", "a")
      lb.bootstrap
      puts "#{server_name} bootstrapped."
      puts "Uploading load balancer config and restarting."
      lb.upload_config(pools.generate_haproxy_config)
    }
  end

  ##
  # Do some validation and start making the API calls for setting everything up.

  def run
    # TODO: Actually do this
    # PoolServers, HAProxy, BoxServers
    pool_servers = PoolServers.new(self, OpenStackConnection.new(ENV))
    lb = HAProxyServer.new(self, OpenStackConnection.new(ENV))
    box_servers = BoxServers.new(self, OpenStackConnection.new(ENV))
    all_servers = pool_servers.all_components + [lb.load_balancer] + box_servers.boxes

    provision_servers(all_servers)
    test_ssh_connections(all_servers)
    lb_bootstrap_pid = etc_host_entry_config(pool_servers, box_servers.boxes, lb.load_balancer)
    
    (pool_servers.all_components + box_servers.boxes).map do |component|
      fork {
        server_name = component.server_name
        $stdout.reopen("#{server_name}.out", "a")
        $stderr.reopen("#{server_name}.err", "a")
        component.bootstrap
        puts "#{server_name} bootstrapped."
      }
    end.each {|pid| Process.wait pid}

    Process.wait lb_bootstrap_pid
    puts "DONE!"
  end

  ##
  # Readers for common components.

  attr_reader :http_pools, :tcp_pools, :boxes

  ##
  # Should be pretty self-explanatory. Just initialize some variables to store
  # component definitions.

  def initialize
    @defaults = {}
    @http_pools = {}
    @tcp_pools = {}
    @boxes = {}
  end

  ##
  # Need an accessor method that does not clash with the setter.

  def defaults_hash
    @defaults
  end

  ##
  # TODO: Not sure if key name and security groups validation should happen here or elsewhere.

  def defaults(opts = {})
    required_keys = [:ssh_key_name, :pem_file, :security_groups]
    key_validation(required_keys, opts)
    if !File.exists?(opts[:pem_file])
      raise StandardError, "Specified .pem file does not exist."
    end
    if opts[:security_groups].empty?
      raise StandardError, "Security groups must be a non-empty array."
    end
    @defaults = opts
  end

  ##
  # Provide convenient access to +GitUrl.new+.

  def git(url)
    GitUrl.new(url)
  end

  ##
  # Convenient access to +ServiceDefinition.new+.

  def service(port, healthcheck_endpoint, healthcheck_port)
    ServiceDefinition.new(port, healthcheck_endpoint, healthcheck_port)
  end

  ##
  # Common method so abstract it.

  def key_validation(keys, hash)
    keys.each do |k|
      if hash[k].nil?
        raise StandardError, "Missing key: :#{k}."
      end
    end
  end

  ##
  # Load balancer configuration is a little special because of configuration uploading but
  # otherwise it's just another pool definition.

  def load_balancer(name, opts = {})
    required_keys = [:count, :image, :vm_flavor, :bootstrap_sequence]
    key_validation(required_keys, opts)
    opts[:name] = name
    @load_balancer = opts
  end

  ##
  # Need a getter for load balancer.

  def get_load_balancer
    @load_balancer
  end

  ##
  # Create an http pool definition. TODO: Do better validation here as well.

  def http_pool(name, opts = {})
    if @http_pools[name]
      raise StandardError, "HTTP pool by that name already exists: #{name}."
    end
    required_keys = [:count, :image, :vm_flavor, :bootstrap_sequence, :services]
    key_validation(required_keys, opts)
    (services = opts[:services]).any? && services.all? {|s| s.service?}
    opts[:name] = name
    @http_pools[name] = opts
  end

  ##
  # Same as for +http_pool+ but instead we create a TCP pool.

  def tcp_pool(name, opts = {})
    if @tcp_pools[name]
      raise StandardError, "TCP pool by that name already exists: #{name}."
    end
    required_keys = [:count, :image, :vm_flavor, :bootstrap_sequence, :services]
    key_validation(required_keys, opts)
    (services = opts[:services]).any? && services.all? {|s| s.service?}
    opts[:name] = name
    @tcp_pools[name] = opts
  end

  ##
  # We need standalone boxes as well.

  def box(name, opts = {})
    if @boxes[name]
      raise StandardError, "Box by that name already exists: #{name}."
    end
    required_keys = [:count, :image, :vm_flavor, :bootstrap_sequence]
    key_validation(required_keys, opts)
    opts[:name] = name
    @boxes[name] = opts
  end

end
