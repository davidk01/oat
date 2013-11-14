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
  # Do some validation and start making the API calls for setting everything up.

  def run
    # TODO: Actually do this
    # PoolServers, HAProxy, BoxServers
    pool_servers = PoolServers.new(self, OpenStackConnection.new(ENV))
    lb = HAProxyServer.new(self, OpenStackConnection.new(ENV))
    # TODO: Migrate box server compiler stuff as well
    box_servers = BoxServers.new(self, OpenStackConnection.new(ENV))
  end

  attr_reader :defaults, :http_pools, :tcp_pools

  ##
  # Should be pretty self-explanatory. Just initialize some variables to store
  # component definitions.

  def initialize
    @defaults = {}
    @http_pools = {}
    @tcp_pools = {}
    @boxes = []
  end

  ##
  # TODO: Not sure if key name and security groups validation should happen here or elsewhere.

  def defaults(opts = {})
    required_keys = [:ssh_key_name, :pem_file, :security_groups]
    required_keys.each do |k|
      if opts[k].nil?
        raise StandardError, ":#{k} is a required key."
      end
    end
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
