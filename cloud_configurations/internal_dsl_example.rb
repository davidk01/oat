require 'oat'

config = Oat::formation do

  ubuntu = 'emi-ubuntu-12.04.2-server-amd64-11122013'
  boilerplate = [
   git('git://github.scm.corp.ebay.com/dkarapetyan/boilerplate-bootstrap.git')
  ]

  defaults :ssh_key_name => 'milo-qa',
   :pem_file => '/openstratus-keys/milo-qa.pem',
   :security_groups => ['default']

  load_balancer 'lb', :count => 1, :image => ubuntu, :vm_flavor => 'small', 
   :bootstrap_sequence => [
    git('git://github.scm.corp.ebay.com/openstratus-bootstrap-scripts/load-balancer-bootstrap.git')
   ]

  http_pool 'date', :count => 2, :image => ubuntu, :vm_flavor => 'small',
   :bootstrap_sequence => boilerplate + [git('git://github.scm.corp.ebay.com/dkarapetyan/jruby-date-demo.git')],
   :services => [service(8080, '/date', 8080)]

  http_pool 'time', :count => 2, :image => ubuntu, :vm_flavor => 'small',
   :bootstrap_sequence => boilerplate + [git('git://github.scm.corp.ebay.com/dkarapetyan/jruby-time-demo.git')],
   :services => [service(8080, '/time', 8080)]

  tcp_pool 'test-tcp-pool', :count => 2, :image => ubuntu, :vm_flavor => 'tiny',
   :bootstrap_sequence => [git('git://github.scm.corp.ebay.com/openstratus-bootstrap-scripts/noop-bootstrap.git')],
   :services => [service(6379, '/ok', 8081)]

  tcp_pool 'test-tcp-pool2', :count => 2, :image => ubuntu, :vm_flavor => 'tiny',
   :bootstrap_sequence => [git('git://github.scm.corp.ebay.com/openstratus-bootstrap-scripts/noop-bootstrap.git')],
   :services => [service(6380, '/ok', 8081)]

  box 'tester', :count => 1, :image => ubuntu, :vm_flavor => 'small',
   :bootstrap_sequence => boilerplate

end

config.run
