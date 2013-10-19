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
  # security groups, pem file, ssh key name, etc. Need to come up with a better name.

  def defaults_hash
    @defaults_hash ||= ast.defaults.first.value.reduce({}) do |memo, pair|
      if (key = pair.key) == 'security-groups'
        memo[key] = pair.value
      else
        memo[key] = pair.value.first
      end
      memo
    end
  end

end
