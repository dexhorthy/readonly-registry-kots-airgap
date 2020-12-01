variable "nameprefix" {
  description = "instance and network name prefix"
}

provider "google" {
  project = "smart-proxy-839"
  region  = "us-central1"
  zone    = "us-central1-b"
}

locals {
  instances = {
    "jump-box"                      = "f1-micro"
    "staging-cluster"               = "n1-standard-4"
    "staging-registry"              = "n1-standard-2"
    "airgap-production-cluster"     = "n1-standard-4"
    "airgap-production-registry"    = "n1-standard-2"
    "airgap-production-workstation" = "n1-standard-1"
  }

}

resource "google_compute_instance" "airgapped_instance" {
  for_each     = local.instances
  name         = "${var.nameprefix}-${each.key}"
  machine_type = each.value

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-1804-lts"
      size  = 100
    }
  }
  tags = [each.key]

  network_interface {
    network = google_compute_network.airgap_network.self_link
    access_config {
    }
  }
}

