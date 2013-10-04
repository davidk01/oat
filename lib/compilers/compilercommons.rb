require 'rubygems'
require 'bundler/setup'
require 'pegrb'
require 'dsl'

##
# Functionality common across AST transformation classes

class CompilerCommons

  attr_reader :ast

  ##
  # Just set the raw string that will be converted into an AST.

  def initialize(string)
    @dsl_string = string
    @ast = Dsl.parse(string).resolve_bootstrap_sequence_includes
  end

  ##
  # Extract components common to load balancers, pools, and boxes.

  def component_data_hash(component_def, security_groups)
    vm_spec = component_def.vm_spec
    pool_data = {'pool-name' => vm_spec.name,
       'image-name' => vm_spec.image_name,
       'bootstrap-urls' => git_urls(component_def.bootstrap_sequence),
       'security-groups' => security_groups,
       'flavor-name' => component_def.flavor}
  end

  ##
  # Go through the sequence and get the git:// urls. Throw an error for any
  # other type of bootstrap directive for the time being.

  def git_urls(bootstrap_sequence)
    bootstrap_sequence.value.map do |pair_node|
      if (bootstrap_type = pair_node.key) == 'git'
        pair_node.value.value
      else
        raise StandardError, "Current format does not support #{bootstrap_type}."
      end
    end.flatten
  end

  ##
  # security groups, pem file, ssh key name, etc. Need to come up with a better name.

  def defaults_hash
    @defaults_hash ||= ast.defaults.value.first.value.reduce({}) do |memo, pair|
      if (key = pair.key) == 'security-groups'
        memo[key] = pair.value.value
      else
        memo[key] = pair.value.value.first
      end
      memo
    end
  end

end
