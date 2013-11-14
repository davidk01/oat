class HAProxyServer

  attr_reader :load_balancer

  ##
  # We need the configuration string and the OpenStack connector.

  def initialize(config, os_connector)
    @config = config
    @os_connector = os_connector
    initialize_load_balancer
  end

  ##
  # This is called in the constructor and shouldn't be called from anywhere else.

  def initialize_load_balancer
    component_def = @config.load_balancer
    defaults_hash = @config.defaults
    @load_balancer = HAProxyLoadBalancerComponent.new(component_def[:name],
     defaults_hash[:ssh_key_name], defaults_hash[:pem_file],
     @os_connector, defaults_hash[:security_groups], component_def)
  end

end
