# network --bootproto=dhcp --onboot=true
keyboard --xlayouts='es'
lang en_US.UTF-8
timezone "Europe/Madrid"
%include /tmp/ignoredisk.line
zerombr
clearpart --all --initlabel
autopart --type=plain --fstype=xfs --nohome
reboot
graphical
#user --name=ansible --groups=wheel --password='redhat00'
#rootpw --plaintext --lock 'redhat00'
services --enabled=ostree-remount
# ostreesetup --nogpg --url=http://192.168.40.1:8080/repo --osname=rhel --ref=rhel/8/x86_64/edge
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

#### DEBUG POST NOCHROOT ####
mount | grep install
ls -l /run/install/repo/
ls -l /mnt/source/
#### DEBUG POST NOCHROOT ####

# Create Directory structure in the new root filesystem
mkdir -p /mnt/sysroot/root/{ansible-content,container-images}
mkdir -p /mnt/sysroot/var/www/html/{rhel84,DevicesGRUBs}
mkdir -p /mnt/sysroot/var/lib/tftpboot/{rhel84,pxelinux,ipxe,tmp}
mkdir -p /mnt/sysroot/var/lib/tftpboot/rhel84/images

# Copy Ansible Content, Container Images
rsync -av --progress /run/install/repo/ansible-content /mnt/sysroot/root/
rsync -av --progress /run/install/repo/container-images /mnt/sysroot/root/
rsync -av --progress /run/install/repo/tftpboot /mnt/sysroot/root/
rsync -av --progress /run/install/repo/rpms /mnt/sysroot/root/

# Copy images, EFI, isolinux HTTPBOOT
rsync -av --progress /run/install/repo/EFI /mnt/sysroot/var/www/html/rhel84/
rsync -av --progress /run/install/repo/images /mnt/sysroot/var/www/html/rhel84/
rsync -av --progress /run/install/repo/isolinux /mnt/sysroot/var/www/html/rhel84/

# Copy Devices Customized Grub HTTPBOOT
rsync -av --progress /run/install/repo/DevicesGRUBs/grub-httpboot.cfg /mnt/sysroot/var/www/html/rhel84/EFI/BOOT/grub.cfg

# Copy images, EFI, isolinux iPXE-TFTP
rsync -av --progress /run/install/repo/EFI /mnt/sysroot/var/lib/tftpboot/rhel84
rsync -av --progress /run/install/repo/images/pxeboot/ /mnt/sysroot/var/lib/tftpboot/rhel84/images

# Copy Devices Customized Grub iPXE-TFTP
rsync -av --progress /run/install/repo/DevicesGRUBs/grub-ipxe-tftp.cfg /mnt/sysroot/var/lib/tftpboot/rhel84/EFI/BOOT/grub.cfg

# Download kickstarts
rsync -av --progress /run/install/repo/kickstarts /mnt/sysroot/var/www/html/

# Decompress PXE files
rpm2cpio /mnt/sysroot/root/rpms/syslinux-tftpboot-*.rpm | cpio -dimv -D /mnt/sysroot/var/lib/tftpboot/tmp
rsync -av --progress /mnt/sysroot/var/lib/tftpboot/tmp/tftpboot/ /mnt/sysroot/var/lib/tftpboot/pxelinux/
rsync -av --progress /run/install/repo/ipxe/devices.ipxe /mnt/sysroot/var/lib/tftpboot/ipxe

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

# ping -c 4 192.168.40.1

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

cat > /etc/systemd/system/container-image1-rhel84.service <<EOF
# container-image1-rhel84.service

[Unit]
Description=Podman container-image1-rhel84.service
Documentation=man:podman-generate-systemd(1)
Wants=network.target
After=network-online.target

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/container-image1-rhel84.pid %t/container-image1-rhel84.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-image1-rhel84.pid --cidfile %t/container-image1-rhel84.ctr-id --cgroups=no-conmon --replace -d --rm --name image1-rhel84 -p8081:8080 $(uname -n):5000/image1-rhel84:1.0.2
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-image1-rhel84.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-image1-rhel84.ctr-id
PIDFile=%t/container-image1-rhel84.pid
Type=forking

[Install]
WantedBy=multi-user.target default.target
EOF

cat > /etc/systemd/system/container-image2-rhel84.service <<EOF
# container-image2-rhel84.service

[Unit]
Description=Podman container-image2-rhel84.service
Documentation=man:podman-generate-systemd(1)
Wants=network.target
After=network-online.target

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/container-image2-rhel84.pid %t/container-image2-rhel84.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-image2-rhel84.pid --cidfile %t/container-image2-rhel84.ctr-id --cgroups=no-conmon --replace -d --rm --name image2-rhel84 -p8082:8080 $(uname -n):5000/image2-rhel84:1.0.2
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-image2-rhel84.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-image2-rhel84.ctr-id
PIDFile=%t/container-image2-rhel84.pid
Type=forking

[Install]
WantedBy=multi-user.target default.target
EOF

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

# Apache ownership
chown apache:apache -R /var/www/html/
chmod -R 755 /var/www/html/rhel84

# tftpboot permissions
chmod -R 755 /var/lib/tftpboot/rhel84/

# Restore SELinux context
restorecon -v -R /var/www/html/ > /dev/null 2>&1
restorecon -v -R /var/lib/tftpboot/ > /dev/null 2>&1

%end
[pgoku@rhde-dev9 rhel84]$ vim kickstarts/laptop-iso.ks
[pgoku@rhde-dev9 rhel84]$ cat kickstarts/laptop-iso.ks
# network --bootproto=dhcp --onboot=true
keyboard --xlayouts='es'
lang en_US.UTF-8
timezone "Europe/Madrid"
%include /tmp/ignoredisk.line
zerombr
clearpart --all --initlabel
autopart --type=plain --fstype=xfs --nohome
reboot
graphical
#user --name=ansible --groups=wheel --password='redhat00'
#rootpw --plaintext --lock 'redhat00'
services --enabled=ostree-remount
# ostreesetup --nogpg --url=http://192.168.40.1:8080/repo --osname=rhel --ref=rhel/8/x86_64/edge
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

#### DEBUG POST NOCHROOT ####
mount | grep install
ls -l /run/install/repo/
ls -l /mnt/source/
#### DEBUG POST NOCHROOT ####
###################################################################
###
###   MUST BE CREATED THE NEW DIRECTORY STRUCTURE
###
############ /var/www/html/{EFI/images} #### HTTPBOOT
#####    dhcp_filename_efi_default_httpboot: "http://{{ dhcp_server }}/rhel84/EFI/BOOT/BOOTX64.EFI"
#####    dhcp_filename_efi_image2_httpboot: http://{{ dhcp_server }}/rhel84/device-image2/EFI/BOOT/BOOTX64.EFI
#####    dhcp_filename_efi_image1_httpboot: http://{{ dhcp_server }}/rhel84/device-image1/EFI/BOOT/BOOTX64.EFI
############ /var/lib/tftpboot/{EFI/images} #### EFI / iPXE
#####    dhcp_filename_efi_default_ipxe: "rhel84/EFI/BOOT/BOOTX64.EFI"
#####    dhcp_filename_efi_image1_ipxe: rhel84/device-image1/EFI/BOOT/BOOTX64.EFI
#####    dhcp_filename_efi_image2_ipxe: rhel84/device-image2/EFI/BOOT/BOOTX64.EFI
############ /var/lib/tftpboot/ipxe #### EFI / iPXE
#####    dhcp_filename_bios_default_ipxe: "ipxe/devices.ipxe"
#####    dhcp_filename_bios_image1_ipxe:  "ipxe/devices_image1.ipxe"
#####    dhcp_filename_bios_image2_ipxe:  "ipxe/devices_image2.ipxe"
###
###################################################################
# Create Directory structure in the new root filesystem
mkdir -p /mnt/sysroot/root/{ansible-content,container-images}
mkdir -p /mnt/sysroot/var/www/html/{rhel84,DevicesGRUBs}
mkdir -p /mnt/sysroot/var/lib/tftpboot/{rhel84,pxelinux,ipxe,tmp}
mkdir -p /mnt/sysroot/var/lib/tftpboot/rhel84/images

# Copy Ansible Content, Container Images
rsync -av --progress /run/install/repo/ansible-content /mnt/sysroot/root/
rsync -av --progress /run/install/repo/container-images /mnt/sysroot/root/
rsync -av --progress /run/install/repo/tftpboot /mnt/sysroot/root/
rsync -av --progress /run/install/repo/rpms /mnt/sysroot/root/

# Copy images, EFI, isolinux HTTPBOOT
rsync -av --progress /run/install/repo/EFI /mnt/sysroot/var/www/html/rhel84/
rsync -av --progress /run/install/repo/images /mnt/sysroot/var/www/html/rhel84/
rsync -av --progress /run/install/repo/isolinux /mnt/sysroot/var/www/html/rhel84/

# Copy Devices Customized Grub HTTPBOOT
rsync -av --progress /run/install/repo/DevicesGRUBs/grub-httpboot.cfg /mnt/sysroot/var/www/html/rhel84/EFI/BOOT/grub.cfg

# Copy images, EFI, isolinux iPXE-TFTP
rsync -av --progress /run/install/repo/EFI /mnt/sysroot/var/lib/tftpboot/rhel84
rsync -av --progress /run/install/repo/images/pxeboot/ /mnt/sysroot/var/lib/tftpboot/rhel84/images

# Copy Devices Customized Grub iPXE-TFTP
rsync -av --progress /run/install/repo/DevicesGRUBs/grub-ipxe-tftp.cfg /mnt/sysroot/var/lib/tftpboot/rhel84/EFI/BOOT/grub.cfg

# Download kickstarts
rsync -av --progress /run/install/repo/kickstarts /mnt/sysroot/var/www/html/

# Decompress PXE files
rpm2cpio /mnt/sysroot/root/rpms/syslinux-tftpboot-*.rpm | cpio -dimv -D /mnt/sysroot/var/lib/tftpboot/tmp
rsync -av --progress /mnt/sysroot/var/lib/tftpboot/tmp/tftpboot/ /mnt/sysroot/var/lib/tftpboot/pxelinux/
rsync -av --progress /run/install/repo/ipxe/devices.ipxe /mnt/sysroot/var/lib/tftpboot/ipxe

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

# ping -c 4 192.168.40.1

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

cat > /etc/systemd/system/container-image1-rhel84.service <<EOF
# container-image1-rhel84.service

[Unit]
Description=Podman container-image1-rhel84.service
Documentation=man:podman-generate-systemd(1)
Wants=network.target
After=network-online.target

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/container-image1-rhel84.pid %t/container-image1-rhel84.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-image1-rhel84.pid --cidfile %t/container-image1-rhel84.ctr-id --cgroups=no-conmon --replace -d --rm --name image1-rhel84 -p8081:8080 $(uname -n):5000/image1-rhel84:1.0.2
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-image1-rhel84.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-image1-rhel84.ctr-id
PIDFile=%t/container-image1-rhel84.pid
Type=forking

[Install]
WantedBy=multi-user.target default.target
EOF

cat > /etc/systemd/system/container-image2-rhel84.service <<EOF
# container-image2-rhel84.service

[Unit]
Description=Podman container-image2-rhel84.service
Documentation=man:podman-generate-systemd(1)
Wants=network.target
After=network-online.target

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/container-image2-rhel84.pid %t/container-image2-rhel84.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-image2-rhel84.pid --cidfile %t/container-image2-rhel84.ctr-id --cgroups=no-conmon --replace -d --rm --name image2-rhel84 -p8082:8080 $(uname -n):5000/image2-rhel84:1.0.2
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-image2-rhel84.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-image2-rhel84.ctr-id
PIDFile=%t/container-image2-rhel84.pid
Type=forking

[Install]
WantedBy=multi-user.target default.target
EOF

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

# Apache ownership
chown apache:apache -R /var/www/html/
chmod -R 755 /var/www/html/rhel84

# tftpboot permissions
chmod -R 755 /var/lib/tftpboot/rhel84/

# Restore SELinux context
restorecon -v -R /var/www/html/ > /dev/null 2>&1
restorecon -v -R /var/lib/tftpboot/ > /dev/null 2>&1

%end
