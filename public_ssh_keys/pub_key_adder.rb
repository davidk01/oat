Dir["*.pub"].each do |pub_key_file|
  pub_key = File.read(pub_key_file).strip
  puts `echo #{pub_key} >> /root/.ssh/authorized_keys`
  unique_keys = File.readlines('/root/.ssh/authorized_keys').uniq.join
  open('/root/.ssh/authorized_keys', 'w') {|f| f.puts unique_keys}
end
