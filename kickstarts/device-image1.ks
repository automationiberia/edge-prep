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
ostreesetup --nogpg --url=http://192.168.50.1:8080/repo --osname=rhel --ref=rhel/8/x86_64/edge

# Post-installation --NOCHROOT script
%post --nochroot --log=/mnt/sysroot/root/kickstart-post-nonchroot.log
set -x

# Configure the new connections
CON_NAME_1=$(nmcli -t -f NAME,TYPE con show | grep "ethernet" | awk -F':' 'NR==1 {print $1}')
CON_NAME_2=$(nmcli -t -f connection,type dev | grep ethernet | awk -F':' 'NR==2 {print $1}')
DEV_NAME_1=$(nmcli -t -f device,type dev | grep ethernet | awk -F':' 'NR==1 {print $1}')
DEV_NAME_2=$(nmcli -t -f device,type dev | grep ethernet | awk -F':' 'NR==2 {print $1}')

# Get current net configuration
IP_ADDRESS1=$(nmcli con show "$CON_NAME_1" | grep -oP "^IP4.ADDRESS[^ ]*\s*\K.*")
## IP_ADDRESS2=192.168.50.1/24
DHCP_HOSTNAME=$(nmcli con show "$CON_NAME_1" | grep -oP "^DHCP4.OPTION[^ ]*\s*host_name = \K.*")

# Remove all the connections from nmcli
nmcli -t -f name con show | while read connection; do nmcli con del "${connection}"; done

# Add the new network configurations
nmcli con add type ethernet save yes ifname ${DEV_NAME_1} con-name ${DEV_NAME_1} ipv4.addresses "${IP_ADDRESS1}" ipv4.gateway "" connection.autoconnect true ipv4.method manual
## nmcli con add type ethernet save yes ifname ${DEV_NAME_2} con-name ${DEV_NAME_2} ipv4.addresses "${IP_ADDRESS2}" ipv4.gateway "" connection.autoconnect true ipv4.method manual

# Copy the network configurations
cp /etc/sysconfig/network-scripts/* /mnt/sysroot/etc/sysconfig/network-scripts/

# Set the hostname and the host at /etc/hosts
## echo "${IP_ADDRESS2%/*} ${DHCP_HOSTNAME%%.*}-int.${DHCP_HOSTNAME#*.}" >> /mnt/sysroot/etc/hosts
echo "${IP_ADDRESS1%/*} $DHCP_HOSTNAME" >> /mnt/sysroot/etc/hosts
echo "192.168.50.1  rhde-lptp.bcnconsulting.com rhde-lptp" >> /mnt/sysroot/etc/hosts
echo "$DHCP_HOSTNAME" > /mnt/sysroot/etc/hostname

## # It works NetworkManager to version 1.39 or above - https://access.redhat.com/solutions/7055398
## nmcli connection migrate; nmcli -f name,filename connection show

%end

# Post-installation script
%post --log=/root/kickstart-post.log

### Check if the installed system is RHEL 8.x or earlier ###
if [ "$(rpm -E %{rhel})" -le 8 ]; then
    # Check specifically if the version is RHEL 8.4 (or earlier)
    # ISSUE - https://issues.redhat.com/browse/RHELPLAN-59465
    # This check ensures the modification is only made for RHEL 8.4 systems
    if [ "$(rpm -q --queryformat '%{VERSION}' redhat-release)" == "8.4" ]; then
        sed -i '/pam_motd.so/ s/^session[ \t]*optional[ \t]*pam_motd.so/& motd=\/run\/motd.d\/boot-status/' /etc/pam.d/sshd
    fi
fi


cat << EOF > /var/usrlocal/bin/pre-pull-container-image.sh
#!/bin/bash

# List of container images to pull
IMAGES=(
    "automationiberia/ot2024/2048:prod"
    "automationiberia/ot2024/simple-http:prod"
)

# Server URL
SERVER_URL="rhde-lptp.bcnconsulting.com:5000"

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
/bin/chcon -t bin_t /var/usrlocal/bin/pre-pull-container-image.sh
ls -Z /var/usrlocal/bin/pre-pull-container-image.sh


# pre-pull the container images at startup
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

###
### Create a service to launch the container workload and restart
### it on failure
###
cat > /etc/systemd/system/container-httpd.service <<EOF
# container-httpd.service

[Unit]
Description=Podman container-httpd.service
Documentation=man:podman-generate-systemd(1)
Wants=network.target
After=network-online.target

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/container-httpd.pid %t/container-httpd.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-httpd.pid --cidfile %t/container-httpd.ctr-id --cgroups=no-conmon --replace -d --rm --name httpd -p8080:8080 rhde-lptp.bcnconsulting.com:5000/automationiberia/ot2024/simple-http:prod
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-httpd.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-httpd.ctr-id
PIDFile=%t/container-httpd.pid
Type=forking

[Install]
WantedBy=multi-user.target default.target
EOF

# enable httpd container image
systemctl enable container-httpd.service

### Greenboot ###

## Create greenboot check/required.d script

cat << 'EOF' > /etc/greenboot/check/required.d/01-check-packages.sh
#!/bin/bash

# List of required packages
required_packages=("python3-pip" "python3-inotify" "git")

# Check if each package is installed
for package in "${required_packages[@]}"; do
    if ! rpm -q "$package" &>/dev/null; then
        echo "Error: $package is not installed."
        exit 1
    fi
done

echo "All required packages are installed."
EOF

chmod +x /etc/greenboot/check/required.d/01-check-packages.sh


##  # Create the email notification script
##  cat << 'EOF' > /etc/greenboot/red.d/01-email-notification.sh
##  #!/bin/bash
##
##  # Define the email recipient and sender
##  TO_EMAIL="your-email@example.com"
##  FROM_EMAIL="no-reply@example.com"
##
##  # Subject for the email
##  SUBJECT="Greenboot Status Failure Notification"
##
##  # Extract the failure script message from the Greenboot journal
##  script_failed=$(journalctl -u greenboot-status | grep FAILURE | grep Script | head -n 1 | awk '{print $7}')
##
##  # Message to send in the email body
##  BODY="THE OSTREE UPGRADE FAILED!\n\nScript that failed: $script_failed\n\nPlease check the system logs for more details."
##
##  # Send the email using mailx
##  echo -e "$BODY" | mailx -s "$SUBJECT" -r "$FROM_EMAIL" "$TO_EMAIL"
##  EOF
##
##  # Make the email notification script executable
##  chmod +x /etc/greenboot/red.d/01-email-notification.sh


# End of post-install script
%end
