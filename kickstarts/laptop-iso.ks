network --bootproto=dhcp --onboot=true
keyboard --xlayouts='es'
lang en_US.UTF-8
timezone "Europe/Madrid"
zerombr
clearpart --all --initlabel
autopart --type=plain --fstype=xfs --nohome
reboot
graphical
user --name=ansible --groups=wheel --password='redhat00'
rootpw --plaintext --lock 'redhat00'
services --enabled=ostree-remount
ostreesetup --nogpg --url=http://192.168.40.1:8080/repo --osname=rhel --ref=rhel/8/x86_64/edge

%post --nochroot --log=/mnt/sysroot/root/kickstart-post-nonchroot.log
set -x

#### DEBUG POST NOCHROOT ####
mount | grep install
ls -l /run/install/repo/
ls -l /mnt/source/
# Create Directory structure in the new root filesystem
mkdir -p /mnt/sysroot/root/{ansible-content,container-images}
mkdir -p /mnt/sysroot/var/www/html/{rhel84,kickstarts,DevicesGRUBs}

# Copy Ansible Content, Container Images
rsync -av --progress /run/install/repo/ansible-content /mnt/sysroot/root/
rsync -av --progress /run/install/repo/container-images /mnt/sysroot/root/

# Copy images, EFI, isolinux
rsync -av --progress /run/install/repo/EFI /mnt/sysroot/var/www/html/rhel84/
rsync -av --progress /run/install/repo/images /mnt/sysroot/var/www/html/rhel84/
rsync -av --progress /run/install/repo/isolinux /mnt/sysroot/var/www/html/rhel84/

# Copy Devices Customized Grub
rsync -av --progress /run/install/repo/DevicesGRUBs/grub.cfg /mnt/sysroot/var/www/html/rhel84/EFI/BOOT/

# Download kickstarts
rsync -av --progress /run/install/repo/kickstarts/ /mnt/sysroot/var/www/html/

#### DEBUG POST NOCHROOT ####

# Configure the new connections
CON_NAME_1=$(nmcli -t -f NAME,TYPE con show | grep "ethernet" | awk -F':' 'NR==1 {print $1}')
CON_NAME_2=$(nmcli -t -f connection,type dev | grep ethernet | awk -F':' 'NR==2 {print $1}')
DEV_NAME_1=$(nmcli -t -f device,type dev | grep ethernet | awk -F':' 'NR==1 {print $1}')
DEV_NAME_2=$(nmcli -t -f device,type dev | grep ethernet | awk -F':' 'NR==2 {print $1}')

# Get current net configuration
IP_ADDRESS1=$(nmcli con show "$CON_NAME_1" | grep -oP "^IP4.ADDRESS[^ ]*\s*\K.*")
IP_ADDRESS2=192.168.50.1/24
DHCP_HOSTNAME=$(nmcli con show "$CON_NAME_1" | grep -oP "^DHCP4.OPTION[^ ]*\s*host_name = \K.*")

# Remove all the connections from nmcli
nmcli -t -f name con show | while read connection; do nmcli con del "${connection}"; done

# Add the new network configurations
nmcli con add type ethernet save yes ifname ${DEV_NAME_1} con-name ${DEV_NAME_1} ipv4.addresses "${IP_ADDRESS1}" ipv4.gateway "" connection.autoconnect true ipv4.method manual
nmcli con add type ethernet save yes ifname ${DEV_NAME_2} con-name ${DEV_NAME_2} ipv4.addresses "${IP_ADDRESS2}" ipv4.gateway "" connection.autoconnect true ipv4.method manual

# Copy the network configurations
cp /etc/sysconfig/network-scripts/* /mnt/sysroot/etc/sysconfig/network-scripts/

# Set the hostname and the host at /etc/hosts
echo "${IP_ADDRESS2%/*} ${DHCP_HOSTNAME%%.*}-int.${DHCP_HOSTNAME#*.}" >> /mnt/sysroot/etc/hosts
echo "${IP_ADDRESS1%/*} $DHCP_HOSTNAME" >> /mnt/sysroot/etc/hosts
echo "192.168.40.1 rhde-dev9.bcnconsulting.com rhde-dev9" >> /mnt/sysroot/etc/hosts
echo "$DHCP_HOSTNAME" > /mnt/sysroot/etc/hostname

# Create DHCP configuration
mkdir -p /mnt/sysroot/var/lib/dhcpd/
touch /mnt/sysroot/var/lib/dhcpd/dhcpd.leases
restorecon -v /mnt/sysroot/var/lib/dhcpd/dhcpd.leases

# It works NetworkManager to version 1.39 or above - https://access.redhat.com/solutions/7055398
# nmcli connection migrate; nmcli -f name,filename connection show

ping -c 4 192.168.40.1

sync

%end

%post --log=/root/kickstart-post.log

#cat << EOF > /var/usrlocal/bin/pre-pull-container-image.sh
##!/bin/bash
#
## List of container images to pull
#IMAGES=(
#    "rhde-dev9.bcnconsulting.com:5000/image1-rhel84:1.0.1"
#    "library/registry:latest"
#)
#
## Server URL
#SERVER_URL="rhde-dev9.bcnconsulting.com:5000"
#
## Wait for server connectivity
#while true; do
#    if curl -s --head --fail "http://\$SERVER_URL" > /dev/null; then
#        echo "Connectivity to \$SERVER_URL established successfully."
#        break
#    else
#        echo "Unable to connect to \$SERVER_URL. Retrying in 10 seconds..."
#        sleep 10
#    fi
#done
#
## Pull container images from the list
#for IMAGE in "\${IMAGES[@]}"; do
#    retries=5
#    attempt=0
#    while [ \$attempt -lt \$retries ]; do
#        echo "Pulling image: \$IMAGE..."
#        podman pull \$SERVER_URL/\$IMAGE --tls-verify=false
#
#        # Check if the image was pulled successfully
#        if podman images --format "{{.Repository}}:{{.Tag}}" | grep -q "\$SERVER_URL/\$IMAGE"; then
#            echo "Image \$IMAGE pulled successfully."
#            break
#        fi
#
#        echo "Retrying image pull for \$IMAGE in 5 seconds..."
#        attempt=\$((attempt + 1))
#        sleep 5
#    done
#
#    if [ \$attempt -eq \$retries ]; then
#        echo "Failed to pull image \$IMAGE after $retries attempts."
#    fi
#done
#echo "All images pulled successfully."
#EOF
#
#chmod +x /var/usrlocal/bin/pre-pull-container-image.sh
#restorecon -v /var/usrlocal/bin/pre-pull-container-image.sh
#/bin/chcon -t bin_t /var/usrlocal/bin/pre-pull-container-image.sh
#ls -Z /var/usrlocal/bin/pre-pull-container-image.sh
#
#
## pre-pull the container images at startup
#cat > /etc/systemd/system/pre-pull-container-image.service <<EOF
#[Unit]
#Description=Pre-pull container image service
#After=network-online.target
#Wants=network-online.target
#
#[Service]
#Type=oneshot
#TimeoutStartSec=600
#ExecStart=/var/usrlocal/bin/pre-pull-container-image.sh
#
#[Install]
#WantedBy=multi-user.target default.target
#EOF
#
## enable pre-pull container image
#systemctl enable pre-pull-container-image.service
#
## systemd service to manage registry
#mkdir -p /opt/registry/data
#chcon -R -t container_file_t /opt/registry/data
#cat > /etc/systemd/system/container-registry.service <<EOF
## container-registry.service
#
#[Unit]
#Description=Podman container-registry.service
#Documentation=man:podman-generate-systemd(1)
#Wants=network.target
#After=network-online.target pre-pull-container-image.service
#
#[Service]
#Environment=PODMAN_SYSTEMD_UNIT=%n
#Restart=on-failure
#TimeoutStopSec=70
#ExecStartPre=/bin/rm -f %t/container-registry.pid %t/container-registry.ctr-id
#ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-registry.pid --cidfile %t/container-registry.ctr-id --cgroups=no-conmon --replace --name container-registry -dit -p 5000:5000 -v /opt/registry/data:/var/lib/registry rhde-dev9.bcnconsulting.com:5000/library/registry
#ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-registry.ctr-id -t 10
#ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-registry.ctr-id
#PIDFile=%t/container-registry.pid
#Type=forking
#
#[Install]
#WantedBy=multi-user.target default.target
#EOF
#
## Enable the service
#systemctl enable container-registry.service
#
#cat > /etc/systemd/system/container-image1-rhel84.service <<EOF
## container-image1-rhel84.service
#
#[Unit]
#Description=Podman container-image1-rhel84.service
#Documentation=man:podman-generate-systemd(1)
#Wants=network.target
#After=network-online.target pre-pull-container-image.service container-registry.service
#
#[Service]
#Environment=PODMAN_SYSTEMD_UNIT=%n
#Restart=on-failure
#TimeoutStopSec=70
#ExecStartPre=/bin/rm -f %t/container-image1-rhel84.pid %t/container-image1-rhel84.ctr-id
#ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-image1-rhel84.pid --cidfile %t/container-image1-rhel84.ctr-id --cgroups=no-conmon --replace -d --rm --name image1-rhel84 -p8080:8080 laptop-int.bcnconsulting.com:5000/image1-rhel84:1.0.1
#ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-image1-rhel84.ctr-id -t 10
#ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-image1-rhel84.ctr-id
#PIDFile=%t/container-image1-rhel84.pid
#Type=forking
#
#[Install]
#WantedBy=multi-user.target default.target
#EOF

######## DEBUG POST ########

echo ls -l /; ls -l /
echo ls -l /root; ls -l /root
echo ls -l /run/; ls -l /run/
echo ls -l /run/media; ls -l /run/media
echo ls -l /run/mount; ls -l /run/mount
echo ls -l /run/install/repo; ls -l /run/install/repo
echo ls -l /mnt/;ls -l /mnt/
echo ls -l /mnt/source/;ls -l /mnt/source/
find / -name laptop-iso.ks

######## DEBUG POST ########
# Create Directory structure
#mkdir -p /root/{ansible-content,container-images}
#mkdir -p /var/www/html/{rhel84,kickstarts,DevicesGRUBs}
#
## Copy Ansible Content, Container Images
#rsync -av --progress /run/install/repo/ansible-content /root/
#rsync -av --progress /run/install/repo/container-images /root/
#
## Copy images, EFI, isolinux
#rsync -av --progress /run/install/repo/EFI /var/www/html/rhel84/
#rsync -av --progress /run/install/repo/images /var/www/html/rhel84/
#rsync -av --progress /run/install/repo/isolinux /var/www/html/rhel84/
#
## Copy Devices Customized Grub
#rsync -av --progress /run/install/repo/DevicesGRUBs/grub.cfg /var/www/html/rhel84/EFI/BOOT/
#
## Download kickstarts
#rsync -av --progress /run/install/repo/kickstarts/ /var/www/html/

# Restore SELinux context
restorecon -v -R /var/www/html/ > /dev/null 2>&1

%end

