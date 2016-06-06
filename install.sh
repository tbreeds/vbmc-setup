#!/usr/bin/env bash

set -ex

. config

apt-get update
apt-get dist-upgrade -y
apt-get install -y build-essential python-dev bridge-utils ipmitool \
                   libvirt-bin libvirt-dev python-libvirt \
                   qemu-kvm qemu-utils genisoimage

echo "Now!"
sleep 30s
cd /etc/network/

ifdown --force ${ETH_IFACE}

# Massage the network config to enable eth0 as part of a bridge maintaining
# it's static IP address
# NOTE: Disable IPv6 because the ubuntu networking setup is broken for bridge
#       interfaces with both IPv4 and IPv6 addresses
sed -e "s/\(auto\) ${ETH_IFACE}/\1 ${BR_IFACE}/g" \
    -e "s/\(iface\) ${ETH_IFACE} \(inet static\)/\1 ${BR_IFACE} \2/" \
    -e "s/\(iface\) ${ETH_IFACE} \(inet6 static\)/\1 disabled.${BR_IFACE} \2/" \
    -e "/iface br0/a \\
    bridge_ports ${ETH_IFACE}
" \
    -i interfaces

ifup --force --verbose ${BR_IFACE}
cat << EO_RESOLVCONF | resolvconf -a ${BR_IFACE}.inet
nameserver 119.9.60.63
nameserver 119.9.60.62
EO_RESOLVCONF


# Setup a modern pip environment
# purge may fail if these aren't installed 
(
    set +e
    apt-get purge -y python-pip python-tox python-distribute          \
                     python-setuptools python-virtualenv python-wheel
    apt-get purge -y python3-pip python3-tox python3-setuptools       \
                     python3-virtualenv python3-wheel
    set -e
)
(
    cd /tmp
    unset PIP_REQUIRE_VIRTUALENV  # Not for installing pip itself
    wget https://bootstrap.pypa.io/get-pip.py
    python get-pip.py
    rm get-pip.py
)
pip install --upgrade tox setuptools virtualenv wheel flake8 bindep

# ZOMG virtual BMC!
pip install virtualbmc

# Create the data-root
mkdir -p ${BASE_PATH}

# For testing we create base systems that boot CirrOS
cd ${BASE_PATH}
wget -o - "http://download.cirros-cloud.net/0.3.4/${IMAGE}"
