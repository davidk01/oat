class BoxServers

  attr_reader :boxes

  ##
  # Same initialization strategy as all the other compilers.

  def initialize(config, os_connector)
    @config = config
    @os_connector = os_connector
    initialize_components
  end

  ##
  # We need to create a +ServerComponent+ instance for each box definition.

  def initialize_components
    raise StandardError, "Boxes are already initialized." if @boxes
    if @config.boxes.empty?
      @boxes = []
    else
      defaults_hash = @config.defaults_hash
      @boxes = @config.boxes.map do |name, box_def|
        box_components = (1..box_def[:count]).map do |vm_index|
          box_component = ServerComponent.new("#{name}-#{vm_index}",
           defaults_hash[:ssh_key_name], defaults_hash[:pem_file],
           @os_connector, defaults_hash[:security_groups], box_def)
        end
      end.flatten
    end
  end

end
