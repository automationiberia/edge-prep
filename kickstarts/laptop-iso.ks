keyboard --xlayouts='es'
lang en_US.UTF-8
timezone "Europe/Madrid"
%include /tmp/ignoredisk.line
zerombr
clearpart --all --initlabel
autopart --type=plain --fstype=xfs --nohome
reboot
graphical
services --enabled=ostree-remount
ostreesetup --osname="rhel" --remote="rhel" --url="file:///run/install/repo/ostree/repo" --ref="rhel/8/x86_64/edge" --nogpg

%pre --log=/mnt/sysroot/root/kickstart-pre.log
USB=$(ls -l /dev/disk/by-id/ | grep usb | grep -v part | awk '{ print $NF }' | sed -r 's/..\/..\///g' | paste -sd "," -)

if [ -n "$USB" ]; then
    echo "ignoredisk --drives=$USB" > /tmp/ignoredisk.line
else
    echo "## No disks are ignored" > /tmp/ignoredisk.line
fi
%end

%post --nochroot --log=/mnt/sysroot/root/kickstart-post-nonchroot.log
set -x

# Define device images
device_images="device-image1 device-image2"

# Create directory structure in the new root filesystem
mkdir -p /mnt/sysroot/root/{ansible-content,container-images}
mkdir -p /mnt/sysroot/var/www/html/{rhel84,DevicesGRUBs}
mkdir -p /mnt/sysroot/var/lib/tftpboot/{rhel84,pxelinux,ipxe,tmp}
mkdir -p /mnt/sysroot/var/lib/tftpboot/rhel84/images

# Create directories for each device image
for image in $device_images; do
    mkdir -p /mnt/sysroot/var/www/html/rhel84/${image}
    mkdir -p /mnt/sysroot/var/lib/tftpboot/rhel84/${image}
done

# Copy Ansible content, container images, vimrc, and RPMs
rsync -av --progress /run/install/repo/ansible-content /mnt/sysroot/root/
rsync -av --progress /run/install/repo/container-images /mnt/sysroot/root/
rsync -av --progress /run/install/repo/files/vimrc /mnt/sysroot/root/.vimrc
rsync -av --progress /run/install/repo/rpms /mnt/sysroot/root/

# Copy HTTPBOOT resources (EFI, GRUB, isolinux, images)
rsync -av --progress /run/install/repo/EFI /mnt/sysroot/var/www/html/rhel84/
rsync -av --progress /mnt/sysroot/usr/lib/grub/x86_64-efi /mnt/sysroot/var/www/html/EFI/BOOT/
rsync -av --progress /run/install/repo/images /mnt/sysroot/var/www/html/rhel84/
rsync -av --progress /run/install/repo/isolinux /mnt/sysroot/var/www/html/rhel84/

# Copy HTTPBOOT GRUB configs and EFI to each device image
for image in $device_images; do
    rsync -av --progress /run/install/repo/EFI /mnt/sysroot/var/www/html/rhel84/${image}/
    rsync -av --progress /mnt/sysroot/usr/lib/grub/x86_64-efi /mnt/sysroot/var/www/html/rhel84/${image}/EFI/BOOT/
    rsync -av --progress /run/install/repo/DevicesGRUBs/grub-httpboot-${image}.cfg /mnt/sysroot/var/www/html/rhel84/${image}/EFI/BOOT/grub.cfg
done

# Copy iPXE-TFTP resources
rsync -av --progress /run/install/repo/EFI /mnt/sysroot/var/lib/tftpboot/rhel84
rsync -av --progress /run/install/repo/images/pxeboot/ /mnt/sysroot/var/lib/tftpboot/rhel84/images

# Copy iPXE GRUB configs and EFI to each device image
for image in $device_images; do
    rsync -av --progress /run/install/repo/EFI /mnt/sysroot/var/lib/tftpboot/rhel84/${image}/
    rsync -av --progress /run/install/repo/DevicesGRUBs/grub-ipxe-tftp-${image}.cfg /mnt/sysroot/var/lib/tftpboot/rhel84/${image}/EFI/BOOT/grub.cfg
done

# Copy common iPXE and HTTPBOOT GRUB configs
rsync -av --progress /run/install/repo/DevicesGRUBs/grub-httpboot.cfg /mnt/sysroot/var/www/html/rhel84/EFI/BOOT/grub.cfg
rsync -av --progress /run/install/repo/DevicesGRUBs/grub-ipxe-tftp.cfg /mnt/sysroot/var/lib/tftpboot/rhel84/EFI/BOOT/grub.cfg

# Download kickstarts
rsync -av --progress /run/install/repo/kickstarts /mnt/sysroot/var/www/html/

# Decompress PXE files
rpm2cpio /mnt/sysroot/root/rpms/syslinux-tftpboot-*.rpm | cpio -dimv -D /mnt/sysroot/var/lib/tftpboot/tmp
rsync -av --progress /mnt/sysroot/var/lib/tftpboot/tmp/tftpboot/ /mnt/sysroot/var/lib/tftpboot/pxelinux/
rsync -av --progress /run/install/repo/ipxe/ /mnt/sysroot/var/lib/tftpboot/ipxe
rm -rf /mnt/sysroot/var/lib/tftpboot/tmp/

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
echo "${IP_ADDRESS2%/*} ${HOSTNAME%%.*}-int.${HOSTNAME#*.}" >> /mnt/sysroot/etc/hosts
echo "${IP_ADDRESS1%/*} $HOSTNAME" >> /mnt/sysroot/etc/hosts
echo "$HOSTNAME" > /mnt/sysroot/etc/hostname


# Create DHCP configuration
mkdir -p /mnt/sysroot/var/lib/dhcpd/
touch /mnt/sysroot/var/lib/dhcpd/dhcpd.leases
restorecon -v /mnt/sysroot/var/lib/dhcpd/dhcpd.leases

# It works NetworkManager to version 1.39 or above - https://access.redhat.com/solutions/7055398
# nmcli connection migrate; nmcli -f name,filename connection show

sync

%end

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

# Get container registry hostname
REGISTRY_HOSTNAME=$(uname -n):5000
echo "Container Registry Hostname: $REGISTRY_HOSTNAME"

# Load images
echo "Loading container images..."
for i in $(ls /root/container-images); do
    podman load -i /root/container-images/$i
done

# Show images
podman images

# Tag the registry image
podman tag docker.io/library/registry:latest $REGISTRY_HOSTNAME/library/registry:latest
podman images

# Tag Images
for IMAGE in $(podman images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>"); do
    NEW_TAG="${REGISTRY_HOSTNAME}/${IMAGE#*/}"  # Remove first part of the name
    podman tag $IMAGE $NEW_TAG
    echo "Tagged $IMAGE as $NEW_TAG"
done

## Remove dangling images separately
#podman images -q --filter "dangling=true" | xargs -r podman rmi -f

## Remove images that are NOT tagged with $REGISTRY_HOSTNAME
#for IMAGE in $(podman images --format "{{.Repository}}:{{.Tag}}" | grep -v "$REGISTRY_HOSTNAME" | grep -v "<none>"); do
#    podman rmi -f $IMAGE
#    echo "Removed: $IMAGE"
#done

# Show final list of images
podman images


# Let use local registry as insecure
cat > /etc/containers/registries.conf.d/local-reg-insecure.conf <<EOF
[[registry]]
location="$(uname -n):5000"
insecure=true
EOF

# systemd service to manage registry
mkdir -p /opt/registry/data
chcon -R -t container_file_t /opt/registry/data
cat > /etc/systemd/system/container-registry.service <<EOF
# container-registry.service

[Unit]
Description=Podman container-registry.service
Documentation=man:podman-generate-systemd(1)
Wants=network.target
After=network-online.target pre-pull-container-image.service

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/container-registry.pid %t/container-registry.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-registry.pid --cidfile %t/container-registry.ctr-id --cgroups=no-conmon --replace --name container-registry -dit -p 5000:5000 -v /opt/registry/data:/var/lib/registry $(uname -n):5000/library/registry:latest
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-registry.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-registry.ctr-id
PIDFile=%t/container-registry.pid
Type=forking

[Install]
WantedBy=multi-user.target default.target
EOF

## Enable the service
systemctl enable container-registry.service

### Create image systemd services
# Define container images names
systemd_images_name=("image1-rhel84" "image2-rhel84")

# Get hostname now
systemd_hostname=$(uname -n)

# Starting host port
systemd_start_port=8081

# Create systemd service for each container image
for i in "${!systemd_images_name[@]}"; do
  image="${systemd_images_name[$i]}"
  port=$((systemd_start_port + i))

  cat > "/etc/systemd/system/container-${image}.service" <<EOF
# container-${image}.service

[Unit]
Description=Podman container-${image}.service
Documentation=man:podman-generate-systemd(1)
Wants=network.target
After=network-online.target

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/container-${image}.pid %t/container-${image}.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-${image}.pid --cidfile %t/container-${image}.ctr-id --cgroups=no-conmon --replace -d --rm --name ${image} --label io.containers.autoupdate=image -p${port}:8080 ${systemd_hostname}:5000/${image}:prod
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-${image}.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-${image}.ctr-id
PIDFile=%t/container-${image}.pid
Type=forking

[Install]
WantedBy=multi-user.target default.target
EOF

done

# Enable the Podman auto-update systemd timer to check periodically:
systemctl enable --now podman-auto-update.timer

# Apache ownership
chown apache:apache -R /var/www/html/
chmod -R 755 /var/www/html/rhel84

# tftpboot permissions
chmod -R 755 /var/lib/tftpboot/rhel84/

# Restore SELinux context
restorecon -v -R /var/www/html/ > /dev/null 2>&1
restorecon -v -R /var/lib/tftpboot/ > /dev/null 2>&1

## Disable  gnome-initial-setup.service
if grep -q "^InitialSetupEnable=" /etc/gdm/custom.conf; then
    sed -i 's/^InitialSetupEnable=.*/InitialSetupEnable=false/' /etc/gdm/custom.conf
elif grep -q "^\[daemon\]" /etc/gdm/custom.conf; then
    sed -i '/^\[daemon\]/a InitialSetupEnable=false' /etc/gdm/custom.conf
else
    echo -e "\n[daemon]\nInitialSetupEnable=false" >> /etc/gdm/custom.conf
fi

%end
