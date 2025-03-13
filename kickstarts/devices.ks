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

%post --log=/root/kickstart-post.log
set -x

# Set a fixed IP configuration using DHCP-derived information
# Fetch the connection name and current IP address
conn_name=$(nmcli con show | grep -v UUID | head -n 1 | awk '{print $1}')
IP_ADDRESS=$(nmcli conn show $conn_name | grep ip_address | awk '{print $4}')
dhcp_hostname=$(nmcli con show $conn_name | grep -oP "^DHCP4.OPTION[^ ]*\s*host_name = \K.*")

# Display fetched information
echo "Connection Name: $conn_name"
echo "IP Address: $IP_ADDRESS"
echo "dhcp_hostname: $dhcp_hostname"

echo "$IP_ADDRESS $dhcp_hostname" >> /etc/hosts
echo "192.168.40.1 rhde-dev9.bcnconsulting.com rhde-dev9" >> /etc/hosts
echo "$dhcp_hostname" > /etc/hostname

mkdir -p /var/lib/dhcpd/
touch /var/lib/dhcpd/dhcpd.leases
restorecon -v /var/lib/dhcpd/dhcpd.leases

# Modify the connection to use a static IP
nmcli con mod $conn_name ipv4.dns-search bcnconsulting.com
nmcli con mod $conn_name ipv4.addresses $IP_ADDRESS
nmcli con mod $conn_name ipv4.method manual

# Restart the network connection

echo "DEBUG INFORMATION"
lsblk
df -h
ip -br a
nmcli -f name,filename connection show
ip route
echo "/ listing"; ls -l /
echo "/var/ listing"; ls -l /var
echo "/var/etc listing"; ls -l /var/etc
echo "/var/etc/NetworkManager listing"; ls -l /var/etc/NetworkManager
echo "/var/etc/NetworkManager/system-connections/ listing"; ls -l /var/etc/NetworkManager/system-connections/
ls -l /usr
ls -l /etc
echo "DEBUG INFORMATION"

mkdir -p /etc/NetworkManager/system-connections/
rm -f /etc/sysconfig/network-scripts/ifcfg-${conn_name}
cp /run/NetworkManager/system-connections/default_connection.nmconnection /etc/NetworkManager/system-connections/${conn_name}.nmconnection

ping -c 4 192.168.40.1

########## PODMAN autoupdate rootless
# create systemd user directories for rootless services, timers, and sockets
# mkdir -p /var/home/ansible/.config/systemd/user/default.target.wants
# mkdir -p /var/home/ansible/.config/systemd/user/sockets.target.wants
# mkdir -p /var/home/ansible/.config/systemd/user/timers.target.wants
# mkdir -p /var/home/ansible/.config/systemd/user/multi-user.target.wants

cat << EOF > /var/usrlocal/bin/pre-pull-container-image.sh
#!/bin/bash
# List of container images to pull
IMAGES=(
    "simple-http:prod"
    "laptop-rhel84:1.0.2"
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

chmod +x /var/usrlocal/bin/pre-pull-container-image.sh
restorecon -v /var/usrlocal/bin/pre-pull-container-image.sh
chcon -t bin_t /var/usrlocal/bin/pre-pull-container-image.sh
ls -Z /var/usrlocal/bin/pre-pull-container-image.sh

# pre-pull the container images at startup to avoid delay in http response
cat > /etc/systemd/system/pre-pull-container-image.service <<EOF
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

# enable pre-pull container image
systemctl enable pre-pull-container-image.service

%end
