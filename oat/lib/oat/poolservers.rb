class PoolServers

  class TCPPool < Struct.new(:components, :pool_definition)

    def to_haproxy_data
      pool_name = pool_definition[:name]
      pool_definition.services.map do |service_def|
        port = service_def.service_port
        healthcheck_endpoint = service_def.healthcheck_endpoint
        healthcheck_port = service_def.healthcheck_port
        ["listen #{pool_name}-#{port}",
         "  mode tcp",
         "  option httpchk GET #{healthcheck_endpoint}",
         "  balance leastconn",
         "  bind *:#{port}",
         "",
         components.map do |c| 
           "  server #{c.server_name} #{c.ip_address}:#{port} check port #{healthcheck_port}"
         end.join("\n")].join("\n")
      end.join("\n\n")
    end

  end

  class HTTPPool < Struct.new(:components, :pool_definition)

    ##
    # Wrap everything and return it to be used in the actual haproxy configuration generation.

    def to_haproxy_data
      pool_name = pool_definition[:name]
      pool_definition.services.map do |service_def|
        service_port = service_def.service_port
        healthcheck_endpoint = service_def.healthcheck_endpoint
        healthcheck_port = service_def.healthcheck_port
        acl = [
         "  acl #{pool_name}-#{service_port} hdr_beg(host) -i #{pool_name}.vip",
         "  use_backend #{pool_name}-#{service_port} if #{pool_name}-#{service_port}"].join("\n")
        servers = components.map do |c|
          "  server #{c.server_name} #{c.ip_address}:#{service_port} check port #{healthcheck_port}"
        end.join("\n")
        backend = [
         "backend #{pool_name}-#{service_port}",
         "  option httpchk GET #{healthcheck_endpoint}", 
         servers].join("\n")
        {:port => service_port, :acl => acl, :backend => backend}
      end
    end

  end

  attr_reader :http_server_components, :tcp_server_components, :tcp_pool_mappings, :http_pool_mappings

  ##
  # Need the configuration holder and OpenStack connection.

  def initialize(config, os_connector)
    @config = config
    @os_connector = os_connector
    @tcp_pool_mappings = Hash.new {|h, k| h[k] = []}
    @http_pool_mappings = Hash.new {|h, k| h[k] = []}
    initialize_components
  end

  ##
  # Get all the components together in one fell swoop and cache the results.

  def all_components
    @all_components ||= (http_server_components + tcp_server_components)
  end

  ##
  # Configuration format is now more explicit about pool types, service ports and healthcheck urls so
  # there is less magic going on.

  def initialize_components
    if (@http_server_components && @tcp_server_components)
      raise StandardError, "Components already initialized."
    end
    @http_server_components, @tcp_server_components = [], []
    defaults = @config.defaults
    security_groups = defaults[:security_groups]
    ssh_key_name, pem_file = defaults[:ssh_key_name], defaults[:pem_file]
    @http_server_components = @config.http_pools.map do |name, pool_options|
      server_components = (1..pool_options[:count]).map do |vm_index|
        ServerComponent.new("#{name}-#{vm_index}", ssh_key_name, pem_file,
         @os_connector, security_groups, pool_options)
      end
      @http_pool_mappings[name] = HTTPPool.new(server_components, pool_options)
      server_components
    end.flatten
    @tcp_server_components = @config.tcp_pools.map do |name, pool_options|
      server_components = (1..pool_options[:count]).map do |vm_index|
        ServerComponent.new("#{name}-#{vm_index}", ssh_key_name, pem_file,
         @os_connector, security_groups, pool_options)
      end
      @tcp_pool_mappings[name] = TCPPool.new(server_components, pool_options)
      server_components
    end.flatten
  end

  ##
  # To generate the haproxy config we need to verify that each component actually has an IP address
  # which means that get server must have been called at some point on each component. Here we only verify
  # calling +ip_address on the component is allowed and die otherwise.

  def generate_haproxy_config
    all_components.each(&:ip_address)
    grouped_http_data = @http_pool_mappings.map {|k, v| v.to_haproxy_data}.
     flatten.group_by {|d| d[:port]}
    # frontend http definitions with acls
    frontend_defs = grouped_http_data.map do |port, haproxy_datas|
      frontend_header = "frontend http-in-#{port}\n  bind *:#{port}\n\n"
      acls = haproxy_datas.map {|port_acl_backend| port_acl_backend[:acl]}.join("\n")
      frontend_header + acls
    end.join("\n\n")
    # backend http servers
    http_backend_servers = grouped_http_data.map do |port, haproxy_datas|
      haproxy_datas.map {|port_acl_backend| port_acl_backend[:backend]}.join("\n\n")
    end.join("\n\n")
    # tcp backend
    tcp_backend = @tcp_pool_mappings.map {|k, v| v.to_haproxy_data}.join("\n\n")
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
     # put it all together
     [preamble, frontend_defs, http_backend_servers, tcp_backend].join("\n\n")
  end

end
