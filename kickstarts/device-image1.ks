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
