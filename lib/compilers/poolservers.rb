require File.expand_path('../cloudformation', File.dirname(__FILE__))
require File.expand_path('./compilercommons', File.dirname(__FILE__))

class PoolServersCompiler < CompilerCommons

  attr_reader :http_server_components, :tcp_server_components

  ##
  # Need the configuration string and OpenStack connection.

  def initialize(dsl_string, os_connector)
    super(dsl_string)
    @os_connector = os_connector
    initialize_components
  end

  ##
  # Get all the components together in one fell swoop and cache the results.

  def all_components
    @all_components ||= (http_server_components + tcp_server_components)
  end

  ##
  # Any pool block that does not expose ports is assumed to be an HTTP
  # server component and the load balancer will automatically route :80, :8080
  # to that component. This means any pool that does expose ports will get a TCP
  # entry in HAProxy and will be load balanced based on exposed ports. This leads
  # to potential load balancing conflicts. (TODO: Add conflict detection, box component initialization)

  def initialize_components
    if (@http_server_components && @tcp_server_components)
      raise StandardError, "Components already initialized."
    end
    @http_server_components, @tcp_server_components = [], []
    defaults = defaults_hash
    security_groups = defaults['security-groups']
    ssh_key_name, pem_file = defaults['ssh-key-name'], defaults['pem-file']
    ast.pools.value.each do |pool_def|
      vm_spec = pool_def.vm_spec
      pool_data = component_data_hash(pool_def, security_groups)
      pool_data['load-balance-ports'] = pool_def.ports
      server_components = (1..vm_spec.count.value).map do |vm_index|
        server_component = ServerComponent.new("#{vm_spec.name}-#{vm_index}",
         ssh_key_name, pem_file, @os_connector, pool_data)
      end
      if pool_def.ports
        @tcp_server_components.concat(server_components)
      else
        @http_server_components.concat(server_components)
      end
    end
  end

end
