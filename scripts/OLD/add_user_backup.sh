#!/bin/bash

# Création du compte 'backup' qui va faire partie de chaque script de setup
sudo useradd -m -s /bin/bash backup 2>/dev/null || echo "User 'backup' already exists"
sudo mkdir -p /home/backup/.ssh
sudo chmod 700 /home/backup/.ssh
sudo cp /home/ec2-user/.ssh/authorized_keys /home/backup/.ssh/authorized_keys 
sudo chown -R backup:backup /home/backup/.ssh


# Droits de lecture pour Apache, FTP, PHP
sudo setfacl -R -m u:backup:rx /etc/httpd/sites-available
sudo setfacl -R -m u:backup:rx /srv/www

# Droits de lecture pour DNS
sudo setfacl -m u:backup:r /etc/named.conf
sudo setfacl -R -m u:backup:rx /var/named
