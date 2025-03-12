# RHEL Setup and Ansible Collection Download

This repository provides Ansible playbooks and variables for setting up a Red Hat Enterprise Linux (RHEL) system, installing necessary tools, downloading and installing Ansible collections, and downloading the RHEL ISO for offline setup.

## System Setup

Ensure your system is up to date and ready for the installation of necessary tools:

```bash
$ sudo dnf update
$ sudo dnf install ansible-navigator ansible-builder ansible-core vim-enhanced vim nmap net-tools bind-utils git container-tools
```

## Downloading and Installing Ansible infra.osbuild Collections

To install an Ansible collection on a disconnected host:

### Download the Collection

Run the following command to download the collection:

```bash
$ ansible-galaxy collection download infra.osbuild -p collections-download
```

### Archive the Downloaded Collection

Once the collection is downloaded, create an archive:


```bash
$ tar cvfz collections-infra-osbuild.tar.gz collections-download
```

### Transfer the Archive to the Target Node

Use `scp` to transfer the archive to the target system:

```bash
$ scp collections-infra-osbuild.tar.gz rhde-destination-host:~/.
```

### Extract and Install the Collection

On the target node:

```bash
$ mkdir basic_install; cd basic_install $ mv collections-infra-osbuild.tar.gz basic_install/. ; cd basic_install $ tar xvfz collections-infra-osbuild.tar.gz
```

Install the collection using the following command:

```bash
$ ansible-galaxy collection install collections-download/*.tar.gz -p collections/
```
## osbuild_setup_server

```bash
$ ansible-playbook infra.osbuild.osbuild_setup_server -i inventory -e 'rhc_state=absent'
```

## Running the Playbook

To run the playbook that will download

### Explanation:

- `playbooks/download_iso.yaml`: The path to the playbook that downloads and sets up the RHEL ISO.
- `-i playbooks/local-inventory.yaml`: The inventory file containing the host configuration.
- `-e@vars/download_iso_vars.yaml`: The variables file that contains necessary configurations for the ISO download and authentication.

## Variables for ISO Download

In order to run the playbook, you will need to define the following variables in the `vars/download_iso_vars.yaml` file:

```yaml
# offline_token: The offline token used for authentication with Red Hat APIs. It can be taken from https://access.redhat.com/management/api
offline_token: ''

# rhel_iso_version: The version of the RHEL ISO to download (e.g., rhel92). It can be downloaded from https://access.redhat.com/downloads/content/479/ver=/rhel---9/9.4/x86_64/product-software
rhel_iso_version: "rhel92"

# rhel_iso_sha_value: The SHA256 checksum of the RHEL ISO for integrity verification
rhel_iso_sha_value: a18bf014e2cb5b6b9cee3ea09ccfd7bc2a84e68e09487bb119a98aa0e3563ac2

## Repository Structure

│
├── playbooks/
│   ├── download_iso.yaml         # Playbook to download the RHEL ISO
│   └── local-inventory.yaml      # Ansible inventory configuration
│
├── vars/
│   └── download_iso_vars.yaml    # Variables for ISO download and authentication
│
└── README.md                     # Documentation on how to use the repository

