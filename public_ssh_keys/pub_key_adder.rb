Dir["*.pub"].each do |pub_key_file|
  pub_key = File.read(pub_key_file).strip
  puts `echo #{pub_key} >> /root/.ssh/authorized_keys`
end
