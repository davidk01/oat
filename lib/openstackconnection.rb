require 'rubygems'
require 'openstack'

class OpenStackConnection

  def initialize(opts = {})
    ['OS_AUTH_URL', 'OS_TENANT_ID', 'OS_TENANT_NAME', 
      'OS_USERNAME', 'OS_PASSWORD'].each do |var|
      if opts[var].nil?
        STDERR.puts "Make sure you have sourced the openstack rc file to set up the proper ENV variables."
        raise StandardError, "#{var} needs to be defined."
      end
      @env = opts
    end
  end

  def get_connection
    OpenStack::Connection.create(
      :username => @env['OS_USERNAME'],
      :auth_method => 'password',
      :auth_url => @env['OS_AUTH_URL'],
      :tenant => @env['OS_TENANT_NAME'],
      :authtenant_id => @env['OS_TENANT_ID'],
      :api_key => @env['OS_PASSWORD'])
  end

end
