# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.15.5"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    # see https://github.com/hashicorp/terraform-provider-random
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.8"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "prefix" {
  type    = string
  default = "terraform-debian-example"
}

variable "vm_count" {
  type    = number
  default = 1
}

variable "network_cidr" {
  type    = string
  default = "10.17.3.0/24"
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.8/docs/resources/network
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.8/docs/resources/network.md
resource "libvirt_network" "example" {
  name = var.prefix
  forward = {
    nat = {
      ports = [
        {
          start = 1024
          end   = 65535
        }
      ]
    }
  }
  ips = [
    {
      address = cidrhost(var.network_cidr, 1)
      netmask = cidrnetmask(var.network_cidr)
      dhcp = {
        ranges = [
          {
            start = cidrhost(var.network_cidr, 2)
            end   = cidrhost(var.network_cidr, -2)
          }
        ]
      }
    }
  ]
}

# create a cloud-init cloud-config.
# NB this creates an iso image that will be used by the NoCloud cloud-init datasource.
# see journalctl -u cloud-init
# see /run/cloud-init/*.log
# see https://cloudinit.readthedocs.io/en/latest/topics/examples.html#disk-setup
# see https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html#datasource-nocloud
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.8/docs/resources/cloudinit_disk
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.8/docs/resources/cloudinit_disk.md
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.8/internal/provider/cloudinit_disk_resource.go#L291-L341
resource "libvirt_cloudinit_disk" "example" {
  count = var.vm_count
  name  = "${var.prefix}${count.index}-cloudinit.iso"
  # NB in debian trixie (13) setting dhcp6 to false does not actually disable ipv6,
  #    it just prevents cloud-init from adding the iface eth0 inet6 dhcp line to the
  #    /etc/network/interfaces.d/50-cloud-init file. that inet6 ifupdown method no
  #    longer works in debian trixie (13) because it expects to find the dhclient
  #    binary which no longer exists by default (the isc-dhcp-client package is
  #    deprecated, and is no longer installed by default; it was replaced by the
  #    dhcpcd-base package, which provides the dhcpcd binary).
  #    see https://packages.debian.org/trixie/isc-dhcp-client
  #    see https://packages.debian.org/trixie/dhcpcd-base
  #    see https://packages.debian.org/trixie/ifupdown
  network_config = <<-EOF
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: false
  EOF
  meta_data      = <<-EOF
  EOF
  user_data      = <<-EOF
  #cloud-config
  fqdn: example${count.index}.test
  manage_etc_hosts: true
  users:
    - name: vagrant
      lock_passwd: false
      ssh_authorized_keys:
        - ${jsonencode(trimspace(file("~/.ssh/id_rsa.pub")))}
  chpasswd:
    expire: false
    users:
      - name: vagrant
        password: '$6$rounds=4096$NQ.EmIrGxn$rTvGsI3WIsix9TjWaDfKrt9tm3aa7SX7pzB.PSjbwtLbsplk1HsVzIrZbXwQNce6wmeJXhCq9YFJHDx9bXFHH.'
  disk_setup:
    /dev/disk/by-id/wwn-0x000000000000ab00:
      table_type: gpt
      layout:
        - [100, 83]
      overwrite: false
  fs_setup:
    - label: data
      device: /dev/disk/by-id/wwn-0x000000000000ab00-part1
      filesystem: ext4
      overwrite: false
  mounts:
    - [/dev/disk/by-id/wwn-0x000000000000ab00-part1, /data, ext4, 'defaults,discard,nofail', '0', '2']
  runcmd:
    - sed -i '/vagrant insecure public key/d' /home/vagrant/.ssh/authorized_keys
  EOF
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.8/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.8/docs/resources/volume.md
resource "libvirt_volume" "example_cloudinit" {
  count = var.vm_count
  pool  = "default"
  name  = "${var.prefix}${count.index}-cloudinit.iso"
  create = {
    content = {
      url = libvirt_cloudinit_disk.example[count.index].path
    }
  }
}

# this uses the vagrant debian image imported from https://github.com/rgl/debian-vagrant.
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.8/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.8/docs/resources/volume.md
resource "libvirt_volume" "example_root" {
  count    = var.vm_count
  pool     = "default"
  name     = "${var.prefix}${count.index}-root.img"
  capacity = 16 * 1024 * 1024 * 1024 # GiB. the root FS is automatically resized by cloud-init growpart (see https://cloudinit.readthedocs.io/en/latest/topics/examples.html#grow-partitions).
  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    format = {
      type = "qcow2"
    }
    path = "/var/lib/libvirt/images/debian-13-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
  }
}

# a data disk.
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.8/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.8/docs/resources/volume.md
resource "libvirt_volume" "example_data" {
  count    = var.vm_count
  pool     = "default"
  name     = "${var.prefix}${count.index}-data.img"
  capacity = 32 * 1024 * 1024 * 1024 # GiB.
  target = {
    format = {
      type = "qcow2"
    }
  }
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.8/docs/resources/domain
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.8/docs/resources/domain.md
resource "libvirt_domain" "example" {
  count       = var.vm_count
  name        = "${var.prefix}${count.index}"
  description = "created from ${path.cwd}"
  running     = true
  type        = "kvm"
  vcpu        = 2
  memory      = 1024
  memory_unit = "MiB"
  features = {
    acpi = true
    apic = {}
    pae  = true
  }
  metadata = {
    xml = <<-EOF
      <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
        <libosinfo:os id="http://debian.org/debian/13"/>
      </libosinfo:libosinfo>
      EOF
  }
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
  }
  cpu = {
    mode = "host-passthrough"
  }
  devices = {
    graphics = [
      {
        spice = {
          auto_port = true
          listeners = [
            {
              address = {}
            }
          ]
        }
      }
    ]
    videos = [
      {
        model = {
          type    = "qxl"
          primary = "yes"
          vram    = 65536
          ram     = 65536
          vga_mem = 16384
          heads   = 1
        }
      }
    ]
    controllers = [
      {
        type  = "scsi"
        model = "virtio-scsi"
      },
      {
        type = "virtio-serial"
      }
    ]
    channels = [
      {
        source = {
          unix = {
            mode = "bind"
          }
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      },
      {
        source = {
          spice_vmc = true
        }
        target = {
          virt_io = {
            name = "com.redhat.spice.0"
          }
        }
      }
    ]
    rngs = [
      {
        model = "virtio"
        backend = {
          random = "/dev/urandom"
        }
      }
    ]
    disks = [
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = libvirt_volume.example_root[count.index].pool
            volume = libvirt_volume.example_root[count.index].name
          }
        }
        target = {
          bus = "scsi"
          dev = "sda"
        }
        wwn = format("000000000000aa%02x", count.index)
      },
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = libvirt_volume.example_data[count.index].pool
            volume = libvirt_volume.example_data[count.index].name
          }
        }
        target = {
          bus = "scsi"
          dev = "sdb"
        }
        wwn = format("000000000000ab%02x", count.index)
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.example_cloudinit[count.index].pool
            volume = libvirt_volume.example_cloudinit[count.index].name
          }
        }
        target = {
          bus = "scsi"
          dev = "hdd"
        }
        serial = "cloudinit"
      }
    ]
    interfaces = [
      {
        type = "network"
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.example.name
          }
        }
        wait_for_ip = {}
      }
    ]
  }
}

# see https://developer.hashicorp.com/terraform/language/resources/terraform-data
resource "terraform_data" "example_provision" {
  count = var.vm_count
  provisioner "remote-exec" {
    inline = [
      <<-EOF
      set -eux
      cloud-init --version
      cloud-init status --long --wait
      sudo cloud-init schema --system --annotate
      id
      uname -a
      cat /etc/os-release
      echo "machine-id is $(cat /etc/machine-id)"
      hostname --fqdn
      cat /etc/hosts
      sudo sfdisk -l
      lsblk -x KNAME -o KNAME,SIZE,TRAN,SUBSYSTEMS,FSTYPE,UUID,LABEL,MODEL,SERIAL | cat
      mount | grep -E '^/dev/' | sort
      cat /etc/fstab | grep -E '^\s*[^#]' | sort
      df -h
      sudo tune2fs -l "$(findmnt -n -o SOURCE /data)"
      EOF
    ]
    connection {
      type        = "ssh"
      user        = "vagrant"
      host        = data.libvirt_domain_interface_addresses.example[count.index].interfaces[0].addrs[0].addr
      private_key = file("~/.ssh/id_rsa")
    }
  }
}

data "libvirt_domain_interface_addresses" "example" {
  count  = var.vm_count
  domain = libvirt_domain.example[count.index].name
}

output "ips" {
  value = data.libvirt_domain_interface_addresses.example[*].interfaces[0].addrs[0].addr
}
