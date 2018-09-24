#!/bin/bash
apt-get -y update
apt-get -y install apache2 golang-go git
export PATH=$PATH:/usr/local/go/bin
#source ~/.profile
#
#
# change permissions so we could write to config folder
chown -R ubuntu /etc/apache2/sites-enabled/
chown -R ubuntu /etc/apache2/sites-available/
#
# enable apache modules for revert proxy and ssl redirect
a2enmod proxy
a2enmod proxy_http
a2enmod proxy_balancer
a2enmod lbmethod_byrequests
a2enmod rewrite
a2enmod ssl
#
# redirect to the app and https
echo "<VirtualHost *:80>
  ProxyPass "/"  "http://localhost:8080/"
  ProxyPassReverse "/"  "http://localhost:8080/"

  # enable this for HTTPS redirect
  # need to specify cert details as well
  # or put a cert into ELB
  #RewriteEngine On
  #RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]

  </VirtualHost>
" > /etc/apache2/sites-enabled/000-default.conf
#
# change permissions back
chown -R root /etc/apache2/sites-enabled/
chown -R root /etc/apache2/sites-available/
#
# Start Apache
service apache2 restart
#
# Switch to non-root user
sudo -u ubuntu -i
# clone the app
cd /home/ubuntu
touch test.txt
mkdir -p .ssh
ssh-keyscan -t rsa github.com > .ssh/known_hosts
git clone https://github.com/AssemblyPayments/simple-go-web-app.git app

#
# Build & start the app
cd app
go build main.go
nohup go run main.go &
