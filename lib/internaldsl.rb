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
  # Should be pretty self-explanatory. Just initialize some variables to store
  # component definitions.

  def initialize
    @defaults = {}
    @bootstrap_sequences = {}
    @http_pools = {}
    @tcp_pools = {}
    @boxes = []
  end

  ##
  # TODO: perform better validation on the values as well.

  def defaults(opts = {})
    required_keys = [:ssh_key_name, :pem_file, :security_groups]
    required_keys.each do |k|
      if opts[k].nil?
        raise StandardError, ":#{k} is a required key."
      end
    end
    @defaults = opts
  end

  def git(url)
    GitUrl.new(url)
  end

  ##
  # Create a named bootstrap sequence that can be referenced from various components.

  def bootstrap_sequence(name, *sequence)
    if @bootstrap_sequences[name]
      raise StanardError, "Sequence by that name already exists: #{name}."
    end
    if !sequence.all? {|b| b.git_url?}
      raise StandardError, "Bootstrap sequence must be git:// URL: #{name}."
    end
    @bootstrap_sequences[name] = sequence
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
  # Create an http pool definition. TODO: Do better validation here as well.
  # TODO: Figure out what the best way is to represent service definitions.

  def http_pool(name, opts = {})
    if @http_pools[name]
      raise StandardError, "HTTP pool by that name already exists: #{name}."
    end
    required_keys = [:count, :image, :vm_flavor, :bootstrap_sequence, :services]
    key_validation(required_keys, opts)
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
    @tcp_pools[name] = opts
  end

end
