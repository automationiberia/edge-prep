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
# ostreesetup --nogpg --url=http://192.168.40.1:8080/ostree-repos/type1/repo --osname=rhel --ref=rhel/9/x86_64/edge
ostreesetup --nogpg --url=http://192.168.40.1:8080/repo --osname=rhel --ref=rhel/8/x86_64/edge

%post --nochroot --log=/mnt/sysroot/root/kickstart-post-nonchroot.log
set -x

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

########## PODMAN autoupdate rootless
# create systemd user directories for rootless services, timers, and sockets
# mkdir -p /var/home/ansible/.config/systemd/user/default.target.wants
# mkdir -p /var/home/ansible/.config/systemd/user/sockets.target.wants
# mkdir -p /var/home/ansible/.config/systemd/user/timers.target.wants
# mkdir -p /var/home/ansible/.config/systemd/user/multi-user.target.wants

cat << EOF > /mnt/sysroot/var/usrlocal/bin/pre-pull-container-image.sh
#!/bin/bash

# List of container images to pull
IMAGES=(
    "simple-http:prod"
    "laptop-rhel84:2.0.3"
)

# Server URL
SERVER_URL="rhde-dev9.bcnconsulting.com:5000"

# Wait for server connectivity
while true; do
    if curl -s --head --fail "http://\$SERVER_URL" > /dev/null; then
        echo "Connectivity to \$SERVER_URL established successfully."
        break
    else
        echo "Unable to connect to \$SERVER_URL. Retrying in 10 seconds..."
        sleep 10
    fi
done

# Pull container images from the list
for IMAGE in "\${IMAGES[@]}"; do
    retries=5
    attempt=0
    while [ \$attempt -lt \$retries ]; do
        echo "Pulling image: \$IMAGE..."
        podman pull \$SERVER_URL/\$IMAGE --tls-verify=false

        # Check if the image was pulled successfully
        if podman images --format "{{.Repository}}:{{.Tag}}" | grep -q "\$SERVER_URL/\$IMAGE"; then
            echo "Image \$IMAGE pulled successfully."
            break
        fi

        echo "Retrying image pull for \$IMAGE in 5 seconds..."
        attempt=\$((attempt + 1))
        sleep 5
    done

    if [ \$attempt -eq \$retries ]; then
        echo "Failed to pull image \$IMAGE after $retries attempts."
    fi
done
echo "All images pulled successfully."
EOF

chmod +x /mnt/sysroot/var/usrlocal/bin/pre-pull-container-image.sh
restorecon -v /mnt/sysroot/var/usrlocal/bin/pre-pull-container-image.sh
/mnt/sysroot/bin/chcon -t bin_t /mnt/sysroot/var/usrlocal/bin/pre-pull-container-image.sh
ls -Z /mnt/sysroot/var/usrlocal/bin/pre-pull-container-image.sh


# pre-pull the container images at startup to avoid delay in http response
cat > /mnt/sysroot/etc/systemd/system/pre-pull-container-image.service <<EOF
[Unit]
Description=Pre-pull container image service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
TimeoutStartSec=600
ExecStart=/var/usrlocal/bin/pre-pull-container-image.sh

[Install]
WantedBy=multi-user.target default.target
EOF


# Download ISO from servidor Inter

mkdir -p /mnt/sysroot/var/www/html/mnt/rhel84 /mnt/sysroot/var/www/html/iso
curl -o /mnt/sysroot/var/www/html/iso/rhel84.iso http://192.168.40.1/iso/rhel84.iso
mount -o loop,ro -t iso9660 /mnt/sysroot/var/www/html/iso/rhel84.iso /mnt/sysroot/var/www/html/mnt/rhel84/
cp -avRf /mnt/sysroot/var/www/html/mnt/rhel84/images /mnt/sysroot/var/www/html/rhel84/
cp -avRf /mnt/sysroot/var/www/html/mnt/rhel84/EFI /mnt/sysroot/var/www/html/rhel84/
cp -avRf /mnt/sysroot/var/www/html/mnt/rhel84/isolinux /mnt/sysroot/var/www/html/rhel84/
restorecon -v -R /mnt/sysroot/var/www/html/ > /dev/null 2>&1

sync

%end

%post --log=/root/kickstart-post.log
# enable pre-pull container image
systemctl enable pre-pull-container-image.service
#ln -s /mnt/sysroot/etc/systemd/system/pre-pull-container-image.service /mnt/sysroot/etc/systemd/system/multi-user.target.wants/pre-pull-container-image.service
#ln -s /mnt/sysroot/etc/systemd/system/pre-pull-container-image.service /mnt/sysroot/etc/systemd/system/default.target.wants/pre-pull-container-image.service
