oat (OpenStack API Toolkit)
===========================

Tool for taking declarative descriptions of cloud formations and converting them to API calls to OpenStack that will provision and bootstrap the described cloud formation.


Requirements
============
If you're using `ruby1.8` then the following insturctions should work:
```bash
sudo apt-get install rubygems ruby-dev
sudo gem install bundler trollop openstack json net-ssh --no-ri --no-rdoc
```

If you're using `ruby1.9` then
```bash
sudo apt-get install rubygems ruby-dev
sudo gem install bundler trollop openstack json net-ssh yaml --no-ri --no-rdoc
```

Prerequisites
=============
1. Go to openstratus/
2. Click on "Access & Security"
3. Click on "Keypairs"
4. Click on "+ Create Keypair" and name it something, doesn't really matter what
5. Save .pem file somewhere where you won't lose it and make sure it's `chmod 600`. We need this for everything else we do
6. Go back to "Access & Security" and Click on "API Access"
7. Click on "Download OpenStack RC File" and save it somewhere you'll remember. Just like .pem this is important
8. Clone this repo, cd into it, run "bundle" to get all the gems
9. Source the rc file you just downloaded to set up all the shell variables. When prompted for password 
type in your corp password.
10. Run "ruby vm-provision.rb --help"

Example
=======
```bash
ruby cloud_formation/internal_dsl_example.rb
```
The above command will set up part of the Milo infrastructure for the account that is specified in the rc file
that you downloaded and sourced. This will only work if you have enough resources. In general, take a look
at `cloud_formation` for examples of cloud formation  yaml files.
