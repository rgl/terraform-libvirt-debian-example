# Usage (Ubuntu 22.04 host)

[![Lint](https://github.com/rgl/terraform-libvirt-debian-example/actions/workflows/lint.yml/badge.svg)](https://github.com/rgl/terraform-libvirt-debian-example/actions/workflows/lint.yml)

Create and install the [base Debian 13 UEFI vagrant box](https://github.com/rgl/debian-vagrant).

Install Terraform:

```bash
# see https://github.com/hashicorp/terraform/releases
# renovate: datasource=github-releases depName=hashicorp/terraform
terraform_version='1.12.2'
wget "https://releases.hashicorp.com/terraform/$terraform_version/terraform_${$terraform_version}_linux_amd64.zip"
unzip "terraform_${$terraform_version}_linux_amd64.zip"
sudo install terraform /usr/local/bin
rm terraform terraform_*_linux_amd64.zip
```

Create the infrastructure:

```bash
export CHECKPOINT_DISABLE='1'
export TF_LOG='DEBUG' # TRACE, DEBUG, INFO, WARN or ERROR.
export TF_LOG_PATH="$PWD/terraform.log"
rm -f "$TF_LOG_PATH"
terraform init
terraform plan -out=tfplan
time terraform apply tfplan
```

**NB** if you have errors alike `Could not open '/var/lib/libvirt/images/terraform_example_root.img': Permission denied'` you need to reconfigure libvirt by setting `security_driver = "none"` in `/etc/libvirt/qemu.conf` and restart libvirt with `sudo systemctl restart libvirtd`.

Show information about the libvirt/qemu guest:

```bash
virsh dumpxml terraform_example0
virsh qemu-agent-command terraform_example0 '{"execute":"guest-info"}' --pretty
virsh qemu-agent-command terraform_example0 '{"execute":"guest-network-get-interfaces"}' --pretty
./qemu-agent-guest-exec terraform_example0 id
./qemu-agent-guest-exec terraform_example0 uname -a
ssh-keygen -f ~/.ssh/known_hosts -R "$(terraform output --json ips | jq -r '.[0]')"
ssh "vagrant@$(terraform output --json ips | jq -r '.[0]')"
```

Destroy the infrastructure:

```bash
time terraform destroy -auto-approve
```

List this repository dependencies (and which have newer versions):

```bash
GITHUB_COM_TOKEN='YOUR_GITHUB_PERSONAL_TOKEN' ./renovate.sh
```

# Virtual BMC

You can externally control the VM using the following terraform providers:

* [vbmc terraform provider](https://registry.terraform.io/providers/rgl/vbmc)
  * exposes an [IPMI](https://en.wikipedia.org/wiki/Intelligent_Platform_Management_Interface) endpoint.
  * you can use it with [ipmitool](https://github.com/ipmitool/ipmitool).
  * for more information see the [rgl/terraform-provider-vbmc](https://github.com/rgl/terraform-provider-vbmc) repository.
* [sushy-vbmc terraform provider](https://registry.terraform.io/providers/rgl/sushy-vbmc)
  * exposes a [Redfish](https://en.wikipedia.org/wiki/Redfish_(specification)) endpoint.
  * you can use it with [redfishtool](https://github.com/DMTF/Redfishtool).
  * for more information see the [rgl/terraform-provider-sushy-vbmc](https://github.com/rgl/terraform-provider-sushy-vbmc) repository.
