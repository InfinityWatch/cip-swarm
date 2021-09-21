# cip-swarm
Cyber Investigation Platform based on a single node Docker Swarm

This a derrivative work based on the CAPES stack, particularly capes-docker found here: https://github.com/capesstack/capes-docker. All credit for the ideas behind this project belong to them. 

```
sudo yum install -y git
git clone https://github.com/InfinityWatch/cip-swarm.git
cd wapes
sudo bash deploy_wapes.sh
```
After deployment, set the DNS server in your workstation to the CIP IP address or add the CIP IP address to your DHCP pool (if running one).

TO-DO:
- Add The Hive with Cortex
- Add Docker registry
- Populate Homer dashboard with links
