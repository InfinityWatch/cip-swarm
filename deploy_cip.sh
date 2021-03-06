#!/bin/bash

# Check to see if root level permissions
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo -e "\e[1;31mThis script needs root privileges to run. Please try again using sudo.\e[0m"
    exit
fi

#####################################
#### Random Automation Variables ####
#####################################

# Set your IP address as a variable. This is for instructions below.
IP="$(hostname -I | sed -e 's/[[:space:]]*$//' | awk '{print $1}')"

# Custom domain; default is cip.local
DOMAIN=cip.local

# Update your Host file
echo -e "${IP} ${HOSTNAME}" | tee -a /etc/hosts
echo -e "${IP} ${DOMAIN}" | tee -a /etc/hosts

# Pihole custom lists
CUSTOM_LIST=/var/lib/docker/volumes/cip_pihole/_data/custom.list

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
openssl req -newkey rsa:2048 -nodes -keyout $(pwd)/nginx/ssl/cip.key -x509 -sha256 -days 365 -out $(pwd)/nginx/ssl/cip.crt -subj "/C=WK/ST=MOUNTAINS/L=JABARI/O=CIP/OU=SERVICES/CN=*.${DOMAIN}"
echo -e "\e[1;32mCreating self-signed certificate for Portainer\e[0m."
openssl req -newkey rsa:2048 -nodes -keyout $(pwd)/portainer/ssl/portainer.key -x509 -sha256 -days 365 -out $(pwd)/portainer/ssl/portainer.crt -subj "/C=WK/ST=MOUNTAINS/L=JABARI/O=CIP/OU=PORTAINER/CN=${IP}"

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
	if [ "install ok installed" = "$(dpkg-query -W --showformat='${Status}\n' docker-ce | grep "install ok installed")" ]; then echo -e "\e[1;32mDocker-CE already installed\e[0m. Moving on..."; else echo -e "\e[1;31mDocker-CE not installed\e[0m. Installing now..." && apt-get -qq install -y docker-ce > /dev/null; fi
	if [ "install ok installed" = "$(dpkg-query -W --showformat='${Status}\n' docker-ce-cli | grep "install ok installed")" ]; then echo -e "\e[1;32mDocker-CE CLI already installed\e[0m. Moving on..."; else echo -e "\e[1;31mDocker-CE CLI not installed\e[0m. Installing now..." && apt-get -qq install -y docker-ce-cli > /dev/null; fi
	if [ "install ok installed" = "$(dpkg-query -W --showformat='${Status}\n' containerd.io | grep "install ok installed")" ]; then echo -e "\e[1;32mContainerd.io already installed\e[0m. Moving on..."; else echo -e "\e[1;31mContainerd.io not installed\e[0m. Installing now..." && apt-get -qq install -y containerd > /dev/null; fi
	
	# Ubuntu OS cleanup for Pihole to use port 53 instead of systemd-resolved
	sed -i "s/#DNS=/DNS=8.8.8.8/g" /etc/systemd/resolved.conf
	sed -i "s/#DNSStubListener=yes/DNSStubListener=no/g" /etc/systemd/resolved.conf
	ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
	systemctl restart systemd-resolved.service
	
	fi

# Install Docker-Compose	
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

# Initialize swarm mode
docker swarm init

echo "Create a password for Gitea database"
while true; do
  read -s -p "Password: " gitea_db_pass
  echo
  read -s -p "Password (again): " gitea_db_pass2
  echo
  [ "$gitea_db_pass" = "$gitea_db_pass2" ] && break
  echo "Please try again"
done

# Create docker secrets
echo "Creating Docker Secrets"
openssl rand -base64 16 | docker secret create etherpad_db -
openssl rand -base64 16 | docker secret create etherpad_db_root -
echo $gitea_db_pass | docker secret create gitea_db -
openssl rand -base64 16 | docker secret create gitea_db_root -

# Create the CIP overlay swarm network
echo -e "\e[1;32mCreating CIP Docker network\e[0m."
docker network create --attachable --scope swarm --driver overlay cip_default

# Bring the swarm up
echo "Beginning Swarm stack deployment"
docker stack deploy -c docker-compose.cip.yml cip
docker stack deploy -c docker-compose.portainer.yml cip_portainer

# Wait for NGINX to become available
echo "The NGINX wait for all other containers start so it takes a bit to come up. Give it a minute or three."
while true
do
  STATUS=$(curl -I -k https://${DOMAIN} 2>/dev/null | head -n 1 | cut -d$' ' -f2)
  if [[ ${STATUS} == 200 ]]; then
    echo -e "\e[1;32mNGINX is up!  Accessible at https://${IP}\e[0m"
    break
  else
    echo "NGINX still loading. Trying again in 10 seconds"
  fi
  sleep 10
done

PORTAINER_STATUS=$(curl -I -k https://${IP}:9000 2>/dev/null | head -n 1 | cut -d$' ' -f2)
if [[ $PORTAINER_STATUS == 200 ]]; then 
  echo -e "\e[1;32mPortainer is up! Accessible at https://${IP}:9000\e[0m"; else echo -e "\e[1;31mPortainer is not accessible\e[0m"; fi
echo

# Clean up orphaned swarm services and containers
docker service rm cip_mongo-init-replica 1>/dev/null
docker container prune --force 1>/dev/null
docker volume prune --force 1>/dev/null

# Insert DNS A records into Pihole
cat > "$CUSTOM_LIST" << EOF

$IP $DOMAIN
$IP adguard.$DOMAIN
$IP calc.$DOMAIN
$IP chat.$DOMAIN
$IP chef.$DOMAIN
$IP draw.$DOMAIN
$IP git.$DOMAIN
$IP homer.$DOMAIN
$IP pad.$DOMAIN
$IP pihole.$DOMAIN
$IP portainer.$DOMAIN
$IP vault.$DOMAIN
$IP wiki.$DOMAIN

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
echo -e "The CIP stack has been \e[1;32msuccessfully\e[0m deployed!

Please see the walkthroughs for the post-installation steps on each component.

The CIP stack utilizes Pihole for DNS services. Point your clients or configure your DHCP pool to resolve names to \e[1;33m${IP}\e[0m.

The following services are available:

adguard.${DOMAIN} -------> Adguard DNS Server	
calc.${DOMAIN} ----------> Ethercalc
chat.${DOMAIN} ----------> Rocketchat
chef.${DOMAIN} ----------> Cyberchef
draw.${DOMAIN} ----------> Draw.io
git.${DOMAIN} -----------> Gitea
homer.${DOMAIN} ---------> Homer Dashboard
pad.${DOMAIN} -----------> Etherpad
pihole.${DOMAIN} --------> Pihole DNS Server
portainer.${DOMAIN} -----> Portainer Docker Container Management
vault.${DOMAIN} ---------> Vaultwarden 
wiki.${DOMAIN} ----------> Dokuwiki
"
