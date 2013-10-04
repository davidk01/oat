#
# Cookbook Name:: api-toolkit-setup
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
bash 'apt update' do
  code 'apt-get update'
end

['git', 'curl', 'build-essential'].each do |p|
  package p do
    action :install
  end
end

bash 'install rvm' do
  flags "-l"
  code <<-EOF
    sudo -u #{ENV['SUDO_USER'] || node['user']} -H -s bash -l -c 'curl -L https://get.rvm.io | bash -s'
    sudo -u #{ENV['SUDO_USER'] || node['user']} -H -s bash -l -c 'rvm install 1.9.3'
  EOF
  not_if { `sudo updatedb && locate rvm`.length > 0 }
end

bash 'install bundler and other requirements' do
  flags "-l"
  # make sure running as part of vagrant up doesn't break anything
  working_dir = File.dirname(__FILE__) + "/../../../"
  if working_dir =~ /^\/tmp/
    working_dir = "/vagrant"
  end
  cwd working_dir
  code <<-EOF
    sudo -u #{ENV['SUDO_USER'] || node['user']} -H -s bash -l -c 'rvm use 1.9.3 && gem install bundler --no-ri --no-rdoc'
    sudo -u #{ENV['SUDO_USER'] || node['user']} -H -s bash -l -c 'rvm use 1.9.3 && bundle install && bundle update'
  EOF
end
