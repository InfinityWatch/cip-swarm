#!/bin/bash

# Check to see if root level permissions
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo -e "\e[1;31mThis script needs root privileges to run. Please try again using sudo.\e[0m"
    exit
fi

# Set your IP address as a variable. This is for instructions below.
IP="$(hostname -I | sed -e 's/[[:space:]]*$//' | awk '{print $1}')"

# Update your Host file
echo -e "${IP} ${HOSTNAME}" | tee -a /etc/hosts

# Custom domain; default is wapes.local
DOMAIN=wapes.local

# Pihole custom lists
CUSTOM_LIST=/var/lib/docker/volumes/pihole/_data/custom.list

################################
##### Credential Creation ######
################################

# Create passphrases and set them as variables
etherpad_user_passphrase=$(head -c 100 /dev/urandom | sha256sum | base64 | head -c 32)
etherpad_mysql_passphrase=$(head -c 100 /dev/urandom | sha256sum | base64 | head -c 32)
etherpad_admin_passphrase=$(head -c 100 /dev/urandom | sha256sum | base64 | head -c 32)
gitea_mysql_passphrase=$(head -c 100 /dev/urandom | sha256sum | base64 | head -c 32)
owncloud_mysql_root_passphrase=$(head -c 100 /dev/urandom | sha256sum | base64 | head -c 32)

# Write the passphrases to a file for reference. You should store this securely in accordance with your local security policy.
USER_HOME=$(getent passwd 1000 | cut -d':' -f6)
for i in {etherpad_user_passphrase,etherpad_mysql_passphrase,etherpad_admin_passphrase,gitea_mysql_passphrase,owncloud_mysql_root_passphrase}; do echo "$i = ${!i}"; done > $USER_HOME/wapes_credentials.txt


#####################################
#### Random Automation Variables ####
#####################################

# Detect the Operating System
echo "Detecting Base OS"
	if [ -f /etc/redhat-release ]; then
		OS=centos
		if grep -q "CentOS Linux release 7" /etc/redhat-release; then
			OSVER=7
		elif grep -q "CentOS Linux release 8" /etc/redhat-release; then
			OSVER=8
		else
			echo "We do not support the version of CentOS you are trying to use."
			exit 1
		fi

	elif [ -f /etc/os-release ]; then
		OS=ubuntu
		if grep -q "UBUNTU_CODENAME=bionic" /etc/os-release; then
			OSVER=bionic
		elif grep -q "UBUNTU_CODENAME=focal" /etc/os-release; then
			OSVER=focal
		else
			echo "We do not support your current version of Ubuntu."
			exit 1
		fi

	else
		echo "We were unable to determine if you are using a supported OS."
		exit 1
	fi

	echo "Found OS: $OS $OSVER"


# Set custom settings in nginx.conf
sed -i "s/DOMAINNAME/${DOMAIN}/g" nginx/nginx.conf
sed -i "s/IPADDRESS/${IP}/g" nginx/nginx.conf
sed -i "s/DOMAINNAME/${DOMAIN}/g" nginx/conf.d/*.conf

# Create SSL certificates
mkdir -p $(pwd)/portainer/ssl/
mkdir -p $(pwd)/nginx/{ssl,conf.d}
echo -e "\e[1;32mCreating self-signed certificate for NGINX\e[0m."
openssl req -newkey rsa:2048 -nodes -keyout $(pwd)/nginx/ssl/wapes.key -x509 -sha256 -days 365 -out $(pwd)/nginx/ssl/wapes.crt -subj "/C=WK/ST=MOUNTAINS/L=JABARI/O=WAPES/OU=SERVICES/CN=*.${DOMAIN}"
echo -e "\e[1;32mCreating self-signed certificate for Portainer\e[0m."
openssl req -newkey rsa:2048 -nodes -keyout $(pwd)/portainer/ssl/portainer.key -x509 -sha256 -days 365 -out $(pwd)/portainer/ssl/portainer.crt -subj "/C=WK/ST=MOUNTAINS/L=JABARI/O=WAPES/OU=PORTAINER/CN=${IP}"

################################
########### Docker #############
################################

if [[ $OS == centos ]]; then
	echo "Installing $OS $OSVER prequisites." # https://docs.docker.com/engine/install/centos/
	if yum list installed "yum-utils" >/dev/null 2>&1; then echo -e "\e[1;32mYUM Utilities already installed\e[0m. Moving on..."; else echo -e "\e[1;31mYUM Utilities not installed\e[0m. Installing now..." && yum install -q -y yum-utils; fi
	
	echo "Adding Docker's official GPG key."
	rpm --import https://download.docker.com/linux/centos/gpg

	echo "Adding Docker "Stable" repository."
	yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

	if yum list installed "docker-ce" >/dev/null 2>&1; then echo -e "\e[1;32mDocker-CE already installed\e[0m. Moving on..."; else echo -e "\e[1;31mDocker-CE not installed\e[0m. Installing now..." && yum install -q -y docker-ce; fi
	if yum list installed "docker-ce-cli" >/dev/null 2>&1; then echo -e "\e[1;32mDocker-CE CLI already installed\e[0m. Moving on..."; else echo -e "\e[1;31mDocker-CE CLI not installed\e[0m. Installing now..." && yum install -q -y docker-ce-cli; fi
	if yum list installed "containerd.io" >/dev/null 2>&1; then echo -e "\e[1;32mContainerd.io already installed\e[0m. Moving on..."; else echo -e "\e[1;31mContainerd.io not installed\e[0m. Installing now..." && yum install -q -y containerd.io; fi
	
else
	echo "Installing $OS $OSVER prequisites." # https://docs.docker.com/engine/install/ubuntu/
	if [ "install ok installed" = "$(dpkg-query -W --showformat='${Status}\n' apt-transport-https | grep "install ok installed")" ]; then echo -e "\e[1;32mAPT Transport HTTPS already installed\e[0m. Moving on..."; else echo -e "\e[1;31mAPT Transport HTTPS not installed\e[0m. Installing now..." && apt-get -qq install -y apt-transport-https > /dev/null; fi
	if [ "install ok installed" = "$(dpkg-query -W --showformat='${Status}\n' ca-certificates | grep "install ok installed")" ]; then echo -e "\e[1;32mCA Certificates already installed\e[0m. Moving on..."; else echo -e "\e[1;31mCA Certificates not installed\e[0m. Installing now..." && apt-get -qq install -y ca-certificates > /dev/null; fi
	if [ "install ok installed" = "$(dpkg-query -W --showformat='${Status}\n' curl | grep "install ok installed")" ]; then echo -e "\e[1;32mCURL already installed\e[0m. Moving on..."; else echo -e "\e[1;31mCURL not installed\e[0m. Installing now..." && apt-get -qq install -y curl > /dev/null; fi
	if [ "install ok installed" = "$(dpkg-query -W --showformat='${Status}\n' gnupg | grep "install ok installed")" ]; then echo -e "\e[1;32mGNUPG already installed\e[0m. Moving on..."; else echo -e "\e[1;31mGNUPG not installed\e[0m. Installing now..." && apt-get -qq install -y gnupg > /dev/null; fi
	if [ "install ok installed" = "$(dpkg-query -W --showformat='${Status}\n' lsb-release | grep "install ok installed")" ]; then echo -e "\e[1;32mLSB Release already installed\e[0m. Moving on..."; else echo -e "\e[1;31mLSB Release not installed\e[0m. Installing now..." && apt-get -qq install -y lsb-release > /dev/null; fi
	
	echo "Adding Docker's official GPG key."
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
	
	echo "Adding Docker "Stable" repository."
	echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	
	apt-get -qq update
	if [ "install ok installed" = "$(dpkg-query -W --showformat='${Status}\n' docker-ce-cli | grep "install ok installed")" ]; then echo -e "\e[1;32mDocker-CE CLI already installed\e[0m. Moving on..."; else echo -e "\e[1;31mDocker-CE CLI not installed\e[0m. Installing now..." && apt-get -qq install -y docker-ce-cli > /dev/null; fi
	if [ "install ok installed" = "$(dpkg-query -W --showformat='${Status}\n' containerd.io | grep "install ok installed")" ]; then echo -e "\e[1;32mContainerd.io already installed\e[0m. Moving on..."; else echo -e "\e[1;31mContainerd.io not installed\e[0m. Installing now..." && apt-get -qq install -y containerd > /dev/null; fi
	
	# Ubuntu OS cleanup for Pihole to use port 53 instead of systemd-resolved
	sed -i "s/#DNS=/DNS=8.8.8.8/g" /etc/systemd/resolved.conf
	sed -i "s/#DNSStubListener=yes/DNSStubListener=no/g" /etc/systemd/resolved.conf
	ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
	systemctl restart systemd-resolved.service
	
	fi
	
echo -e "\e[1;32mInstalling Docker Compose\e[0m."
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
	
# Create non-Root users to manage Docker
# You'll still need to run sudo docker [command] until you log out and back in OR run "newgrp - docker".
USER_1K=$(getent passwd 1000 | cut -d':' -f1)
usermod -aG docker "${USER_1K}"

# Set Docker to start on boot and start the daemon
systemctl enable docker.service
systemctl start docker.service

# Create the WAPES network
echo -e "\e[1;32mCreating WAPES Docker network\e[0m."
network create --attachable --subnet 172.18.0.0/16 wapes

# Create Docker volumes
echo -e "\e[1;32mCreating Docker volumes\e[0m."
for i in {dokuwiki,etherpad,gitea,heimdall,mariadb_owncloud,mongo_rocketchat,mysql_etherpad,mysql_gitea,nginx,owncloud,pihole,pihole_dnsmasq,portainer,redis_ethercalc,rocketchat,vaultwarden}; do docker volume create $i; done

# Pull the Docker images quietly
echo -e "\e[1;32mPulling Docker images\e[0m."

array=( ${dokuwiki} ${drawio} ${ethercalc_redis} ${ethercalc} ${etherpad_mysql} ${etherpad} ${gitea_mysql} ${gitea} ${heimdall} ${homer} ${owncloud_mariadb} ${owncloud} ${pihole} ${portainer} ${rocketchat_mongo} ${rocketchat} ${vaultwarden} ${nginx} )
for i in ${array[@]}; do docker pull --quiet $i; done


# Run the Docker containers
echo -e "\e[1;32mRunning Docker containers\e[0m."
# Dokuwiki Container
docker run -d --network wapes --restart unless-stopped --name wapes-dokuwiki -v dokuwiki:/config:z -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC ${dokuwiki}

# Draw.io Container
docker run -d --network wapes --restart unless-stopped --name wapes-draw.io fjudith/draw.io:${drawio_ver}

# Ethercalc Redis Container
docker run -d --network wapes --restart unless-stopped --name wapes-ethercalc-redis -v redis_ethercalc:/data:z ${ethercalc_redis} redis-server --appendonly yes
sleep 5
# Ethercalc Container
docker run -d --network wapes --restart unless-stopped --name wapes-ethercalc -e "REDIS_PORT_6379_TCP_ADDR=wapes-ethercalc-redis" -e "REDIS_PORT_6379_TCP_PORT=6379" ${ethercalc}

# Etherpad MYSQL Container
docker run -d --network wapes --restart unless-stopped --name wapes-etherpad-mysql -v mysql_etherpad:/var/lib/mysql:z -e "MYSQL_DATABASE=etherpad" -e "MYSQL_USER=etherpad" -e "MYSQL_PASSWORD=${etherpad_mysql_passphrase}" -e "MYSQL_RANDOM_ROOT_PASSWORD=yes" ${etherpad_mysql}
# Etherpad Container
docker run -d --network wapes --restart unless-stopped --name wapes-etherpad -v etherpad:/opt/etherpad-lite/var -e "ETHERPAD_TITLE=WAPES" -e "ETHERPAD_PORT=9001" -e "ETHERPAD_ADMIN_PASSWORD=${etherpad_admin_passphrase}" -e "ETHERPAD_ADMIN_USER=admin" -e "ETHERPAD_DB_TYPE=mysql" -e "ETHERPAD_DB_HOST=wapes-etherpad-mysql" -e "ETHERPAD_DB_USER=etherpad" -e "ETHERPAD_DB_PASSWORD=${etherpad_mysql_passphrase}" -e "ETHERPAD_DB_NAME=etherpad" ${etherpad}

# Gitea MYSQL Container
docker run -d --network wapes --restart unless-stopped --name wapes-gitea-mysql -v mysql_gitea:/var/lib/mysql:z -e "MYSQL_DATABASE=gitea" -e "MYSQL_USER=gitea" -e "MYSQL_PASSWORD=${gitea_mysql_passphrase}" -e "MYSQL_RANDOM_ROOT_PASSWORD=yes" ${gitea_mysql}
# Gitea Container
docker run -d --network wapes --restart unless-stopped --name wapes-gitea -v gitea:/data:z -e "DB_TYPE=mysql" -e "DB_HOST=wapes-gitea-mysql:3306" -e "DB_NAME=gitea" -e "DB_USER=gitea" -e "DB_PASSWD=${gitea_mysql_passphrase}" -p 8022:22 ${gitea}

# Heimdall dashboard
docker run -d --network wapes --restart unless-stopped --name wapes-heimdall -v heimdall:/config:z -e PUID=1001 -e PGID=1001 -e "TZ=Etc/UTC" ${heimdall}

# Homer Container - will probably replace Heimdall
docker run -d --network wapes --restart unless-stopped --name wapes-homer -v homer:/www/assets ${homer}

# Owncloud MariaDB Container
docker run -d --network wapes --restart unless-stopped --name wapes-owncloud-mariadb -v mariadb_owncloud:/var/lib/mysql -e "MYSQL_ROOT_PASSWORD=${owncloud_mysql_root_passphrase}" ${owncloud_mariadb}
# Owncloud Container
docker run -d --network wapes --restart unless-stopped --name wapes-owncloud -v owncloud:/var/www/html ${owncloud}

# Pihole Container
docker run -d --network wapes --restart unless-stopped --name wapes-pihole -v pihole:/etc/pihole:z -v pihole_dnsmasq:/etc/dnsmasq.d:z -e "TZ=Etc/UTC" -p 53:53/tcp -p 53:53/udp ${pihole}

# Portainer Container
docker run -d --network wapes --privileged --restart unless-stopped --name wapes-portainer -v portainer:/data:z  -v $(pwd)/portainer/ssl:/certs:z -v /var/run/docker.sock:/var/run/docker.sock -p 9000:9000 ${portainer} --ssl --sslcert /certs/portainer.crt --sslkey /certs/portainer.key --no-analytics

# Rocket Chat MongoDB Container
docker run -d --network wapes --restart unless-stopped --name wapes-rocketchat-mongo -v mongo_rocketchat:/data/db:z -v mongo_rocketchat:/data/configdb:z -v mongo_rocketchat:/dump:z ${rocketchat_mongo} mongod --smallfiles --oplogSize 128 --replSet rs1 --storageEngine=mmapv1
sleep 5
docker exec -d wapes-rocketchat-mongo bash -c 'echo -e "replication:\n  replSetName: \"rs01\"" | tee -a /etc/mongod.conf && mongo --eval "printjson(rs.initiate())"'
# Rocket Chat Container
docker run -d --network wapes --restart unless-stopped --name wapes-rocketchat --link wapes-rocketchat-mongo -v rocketchat:/app/uploads -e "MONGO_URL=mongodb://wapes-rocketchat-mongo:27017/rocketchat" -e "MONGO_OPLOG_URL=mongodb://wapes-rocketchat-mongo:27017/local?replSet=rs01" -e "ROOT_URL=http://wapes-rocketchat:3000" ${rocketchat}

# Vaultwarden Container
docker run -d --network wapes --restart unless-stopped --name wapes-vaultwarden -v vaultwarden:/data/ vaultwarden/server:${vaultwarden_ver}

# Nginx Containter
docker run -d --network wapes --restart unless-stopped --name wapes-nginx -v $(pwd)/nginx/ssl/wapes.crt:/etc/nginx/wapes.crt:z -v $(pwd)/nginx/ssl/wapes.key:/etc/nginx/wapes.key:z -v $(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:z -v $(pwd)/nginx/conf.d/:/etc/nginx/conf.d/:z -v nginx:/var/log/nginx/:z -p 80:80 -p 443:443 ${nginx}

cat > "$CUSTOM_LIST" << EOF

$IP $DOMAIN
$IP calc.$DOMAIN
$IP chat.$DOMAIN
$IP cloud.$DOMAIN
$IP draw.$DOMAIN
$IP git.$DOMAIN
$IP heimdall.$DOMAIN
$IP homer.$DOMAIN
$IP pad.$DOMAIN
$IP pihole.$DOMAIN
$IP portainer.$DOMAIN
$IP vault.$DOMAIN
$IP wiki.$DOMAIN
$IP www.$DOMAIN

EOF
################################
### Firewall Considerations ####
################################
# Docker manages this for you with iptables, but in the event you need to add them.
# Port 53/tcp -----	Pihole DNS
# Port 53/udp -----	Pihole DNS
# Port 80/tcp -----	Nginx
# Port 443/tcp ----	Nginx
# Port 8022/tcp ---	Gitea SSH 
# Port 9000/tcp ---	Portainer
# firewall-cmd --add-port=53/tcp --add-port=53/udp --add-port=80/tcp --add-port=443/tcp --add-port=8022/tcp --add-port=9000/tcp --permanent
# firewall-cmd --reload
# firewall-cmd --list-all --zone=docker

#############################################
######### Success Page/Quick README #########
#############################################
echo -e "The WAPES stack has been \e[1;32msuccessfully\e[0m deployed!

Please see the walkthroughs for the post-installation steps on each component.

The WAPES stack utilizes Pihole for DNS services. Point your clients or configure your DHCP pool to resolve names to \e[1;33m${IP}\e[0m.

The following services are available:
	
calc.${DOMAIN} ----------> Ethercalc
chat.${DOMAIN} ----------> Rocketchat
cloud.${DOMAIN} ---------> Owncloud
draw.${DOMAIN} ----------> Draw.io
git.${DOMAIN} -----------> Gitea
heimdall.${DOMAIN} ------> Heimdall Dashboard
homer.${DOMAIN} ---------> Homer Dashboard
pad.${DOMAIN} -----------> Etherpad
pihole.${DOMAIN} --------> Pihole DNS Server
portainer.${DOMAIN} -----> Portainer Docker Container Management
vault.${DOMAIN} ---------> Vaultwarden 
wiki.${DOMAIN} ----------> Dokuwiki
www.${DOMAIN} -----------> Heimdall Dashboard
"
PORTAINER_STATUS=$(curl -I -k https://${IP}:9000 2>/dev/null | head -n 1 | cut -d$' ' -f2)
if [[ $PORTAINER_STATUS == 200 ]]; then echo "Portainer is accessible at https://${IP}:9000"; else echo "Portainer is not accessible"; fi
echo
NGINX_STATUS=$(curl -I -k https://${DOMAIN} 2>/dev/null | head -n 1 | cut -d$' ' -f2)
if [[ $NGINX_STATUS == 200 ]]; then echo "NGINX Reverse Proxy is working!"; else echo "NGINX Reverse Proxy is NOT working, check NGINX docker logs (docker logs wapes-nginx)"; fi
echo