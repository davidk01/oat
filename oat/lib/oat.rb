require "oat/version"
require "oat/openstackconnection"
require "oat/oatdsl"
require "oat/cloudformation"
require "oat/poolservers"
require "oat/haproxyserver"

module Oat

  ##
  # Just a single method that defers to +CloudFormation+ to do the work.

  def self.formation(&blk)
    ::CloudFormation.formation(&blk)
  end

end
