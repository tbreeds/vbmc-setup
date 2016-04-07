#!/bin/bash

id=${1:-1}

. /root/config

IPMI_PORT=$(( 9000 + $id ))

LOCAL_HOSTNAME=$( printf "vbmc-%05d" $id )
INSTANCE_ID=$( printf "iid-%010d" $id )
MAC_ADDRESS=$( printf '00:60:2F:%02X:%02X:%02X\n' \
			$(( ($id >> 16) & 0xFF )) \
			$(( ($id >>  8) & 0xFF )) \
			$(( ($id >>  0) & 0xFF )) )

INSTANCE_PATH="${BASE_PATH}/instances/${LOCAL_HOSTNAME}"
DISK="${INSTANCE_PATH}/disk"
CONFIGDRIVE="${INSTANCE_PATH}/configdrive"
XML_FILE="${INSTANCE_PATH}/libvirt.xml"

mkdir -p "${INSTANCE_PATH}"
cp "$DISK_MASTER" "$DISK"

DTMP=$(mktemp -d)
# Why'owhy can't I get variable expansion in a heredoc?
sed -e "s^@@LOCAL_HOSTNAME@@^${LOCAL_HOSTNAME}^g"	\
    -e "s^@@INSTANCE_ID@@^${INSTANCE_ID}^g"	\
<< "EO_JSON" > "${DTMP}/meta-data"
{
"instance-id": "@@INSTANCE_ID@@",
"local-hostname": "@@LOCAL_HOSTNAME@@"
}
EO_JSON
genisoimage  -output ${CONFIGDRIVE} -volid cidata -joliet -rock \
            ${DTMP}/meta-data >/dev/null 2>&1
rm -rf "${DTMP}"

# Why'owhy can't I get variable expansion in a heredoc?
sed -e "s^@@LOCAL_HOSTNAME@@^${LOCAL_HOSTNAME}^g"	\
    -e "s^@@DISK@@^${DISK}^g"	\
    -e "s^@@CONFIGDRIVE@@^${CONFIGDRIVE}^g"	\
    -e "s^@@MAC_ADDRESS@@^${MAC_ADDRESS}^g"	\
    -e "s^@@BR_IFACE@@^${BR_IFACE}^g"	\
    -e "s^@@HV_TYPE@@^${HV_TYPE}^g"	\
<< "EO_DOMXML" > "${XML_FILE}"
<domain type='@@HV_TYPE@@'>
  <name>@@LOCAL_HOSTNAME@@</name>
  <memory unit='KiB'>524288</memory>
  <currentMemory unit='KiB'>524288</currentMemory>
  <vcpu placement='static'>1</vcpu>
  <os>
    <type arch='x86_64' machine='pc-i440fx-1.6'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='@@DISK@@'/>
      <target dev='hda' bus='ide'/>
      <alias name='ide0-0-0'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='@@CONFIGDRIVE@@'/>
      <target dev='hdb' bus='ide'/>
      <alias name='ide0-0-1'/>
      <address type='drive' controller='0' bus='0' target='0' unit='1'/>
    </disk>
    <controller type='usb' index='0' model='ich9-ehci1'>
      <alias name='usb0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x7'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci1'>
      <alias name='usb0'/>
      <master startport='0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0' multifunction='on'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci2'>
      <alias name='usb0'/>
      <master startport='2'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x1'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci3'>
      <alias name='usb0'/>
      <master startport='4'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x2'/>
    </controller>
    <controller type='pci' index='0' model='pci-root'>
      <alias name='pci.0'/>
    </controller>
    <controller type='ide' index='0'>
      <alias name='ide0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
    </controller>
    <interface type='bridge'>
      <mac address='@@MAC_ADDRESS@@'/>
      <source bridge='@@BR_IFACE@@'/>
      <target dev='tap0'/>
      <model type='rtl8139'/>
      <alias name='net0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </interface>
    <serial type='pty'>
      <source path='/dev/pts/6'/>
      <target port='0'/>
      <alias name='serial0'/>
    </serial>
    <console type='pty' tty='/dev/pts/6'>
      <source path='/dev/pts/6'/>
      <target type='serial' port='0'/>
      <alias name='serial0'/>
    </console>
    <memballoon model='virtio'>
      <alias name='balloon0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </memballoon>
  </devices>
</domain>
EO_DOMXML

virsh --connect "${LIBVIRT_URI}" define --file "${XML_FILE}"
vbmc add --libvirt-uri "${LIBVIRT_URI}" --port $IPMI_PORT $LOCAL_HOSTNAME
vbmc start $LOCAL_HOSTNAME
ipmitool -I lanplus -H 127.0.0.1 -p $IPMI_PORT -U admin -P password \
        power status
# ---
ipmitool -I lanplus -H 127.0.0.1 -p $IPMI_PORT -U admin -P password \
        power on
echo virsh --connect "${LIBVIRT_URI}" console $LOCAL_HOSTNAME
