require File.expand_path('./compilercommons', File.dirname(__FILE__))
require File.expand_path('../cloudformation', File.dirname(__FILE__))

class HAProxyCompiler < CompilerCommons
  attr_reader :load_balancer

  ##
  # We need the configuration string and the OpenStack connector.

  def initialize(dsl_string, os_connector)
    super(dsl_string)
    @os_connector = os_connector
    initialize_load_balancer
  end

  ##
  # This is called in the constructor and shouldn't be called from anywhere else.

  def initialize_load_balancer
    component_def = ast.load_balancer
    vm_spec = component_def.vm_spec
    lb_data = {
      'pool-name' => vm_spec.name,
      'image-name' => vm_spec.image_name,
      'bootstrap-urls' => git_urls(component_def.bootstrap_sequence),
      'security-groups' => defaults_hash['security-groups'],
      'flavor-name' => component_def.flavor
    }
    @load_balancer = HAProxyLoadBalancerComponent.new(vm_spec.name,
     defaults_hash['ssh-key-name'], defaults_hash['pem-file'],
     @os_connector, lb_data)
  end

end
