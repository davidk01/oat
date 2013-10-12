require File.expand_path('../cloudformation', File.dirname(__FILE__))
require File.expand_path('./compilercommons', File.dirname(__FILE__))

class PoolServersCompiler < CompilerCommons

  
  class TCPPool < Struct.new(:components, :ports, :pool_name)

    def to_haproxy_stanza_data
      ports.map do |port|
        ["listen #{pool_name}-#{port}",
         "  mode tcp",
         "  balance leastconn",
         "  bind *:#{port}",
         "",
         components.map {|c| "  server #{c.server_name} #{c.ip_address}:#{port}"}.join("\n")].join("\n")
      end.join("\n\n")
    end

  end

  class HTTPPool < Struct.new(:components, :pool_name)

    ##
    # We also need to keep track haproxy ACL and backend definitions so those pieces
    # should be encapsulated in an object that can then be pieced together into the final
    # configuration.

    class HAProxyHTTPStanzaComponents < Struct.new(:acl_backend_definition, :backend_servers_stanza); end

    ##
    # In turn the HTTP component definitions need to be indexed by port so we need to wrap it in another layer
    # just for good measure. Might be going overboard with typing the data.

    class HAProxyHTTPComponentsIndexedByPort < Struct.new(:port_80, :port_8080); end

    ##
    # Generate the pieces that will go in "frontend http-in-+port+ section.

    def acl_backend_definition(port)
      ["  acl #{pool_name}-#{port} hdr_beg(host) -i #{pool_name}.vip",
       "  use_backend #{pool_name}-#{port} if #{pool_name}-#{port}"].join("\n")
    end

    ##
    # Generate the actual "backend" section.

    def backend_servers_stanza(port)
      ["backend #{pool_name}-#{port}",
       components.map {|c| "  server #{c.server_name} #{c.ip_address}:#{port}"}.join("\n")].join("\n")
    end

    ##
    # We need the +ports+ for acl and backend definitions to be coupled so abstract it here.

    def haproxy_definition_components(port)
      return acl_backend_definition(port), backend_servers_stanza(port)
    end

    ##
    # Wrap everything and return it to be used in the actual haproxy configuration generation.

    def to_haproxy_stanza_data
      HAProxyHTTPComponentsIndexedByPort.new(HAProxyHTTPStanzaComponents.new(*haproxy_definition_components(80)),
       HAProxyHTTPStanzaComponents.new(*haproxy_definition_components(8080)))
    end

  end

  attr_reader :http_server_components, :tcp_server_components, :pool_mappings

  ##
  # Need the configuration string and OpenStack connection.

  def initialize(dsl_string, os_connector)
    super(dsl_string)
    @os_connector = os_connector
    @pool_mappings = Hash.new {|h, k| h[k] = []}
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
        @pool_mappings[vm_spec.name] = TCPPool.new(server_components, pool_def.ports.value.map(&:value), vm_spec.name)
      else
        @http_server_components.concat(server_components)
        @pool_mappings[vm_spec.name] = HTTPPool.new(server_components, vm_spec.name)
      end
    end
  end

  ##
  # To generate the haproxy config we need to verify that each component actually has an IP address
  # which means that get server must have been called at some point on each component. Here we only verify
  # calling +ip_address on the component is allowed and die otherwise.

  def generate_haproxy_config
    all_components.each(&:ip_address)
    tcp_pools, http_80_pools, http_8080_pools = [], [], []
    pool_mappings.map do |pool_name, pool|
      stanza_data = pool.to_haproxy_stanza_data
      if TCPPool === pool
        tcp_pools << stanza_data
      else
        http_80_pools << stanza_data.port_80; http_8080_pools << stanza_data.port_8080
      end
    end
    # lets generate some strings
    preamble = [
     'global',
     '  daemon',
     '  maxconn 1024',
     '',
     'defaults',
     '  mode http',
     '  balance leastconn',
     '  timeout connect 5000ms',
     '  timeout client 50000ms',
     '  timeout server 50000ms',
     '',
     'listen stats :11000',
     '  mode http',
     '  stats enable',
     '  stats realm Haproxy\ Statistics',
     '  stats uri /',
     ''].join("\n")
     frontend_http_80_preamble = [
      'frontend http-in-80',
      '  bind *:80',
      '',
      *http_80_pools.map {|p| p.acl_backend_definition},
      ''].join("\n")
     frontend_http_8080_preamble = [
      'frontend http-in-8080',
      '  bind *:8080',
      '',
      *http_8080_pools.map {|c| c.acl_backend_definition},
      ''].join("\n")
     http_80_backend = http_80_pools.map {|c| c.backend_servers_stanza}.join("\n\n")
     http_8080_backend = http_8080_pools.map {|c| c.backend_servers_stanza}.join("\n\n")
     tcp_backend = tcp_pools.join("\n\n")
     # put it all together
     [preamble, frontend_http_80_preamble, frontend_http_8080_preamble, http_80_backend,
      http_8080_backend, tcp_backend].join("\n\n")
  end

end
