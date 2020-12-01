resource "google_compute_network" "airgap_network" {
  name                    = "${var.nameprefix}-airgap-network"
  auto_create_subnetworks = "true"
}

resource google_compute_firewall "jump_box_ssh" {
  name    = "${var.nameprefix}-jump-tcp-ingress"
  network = google_compute_network.airgap_network.self_link
  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports = ["22"]
  }

  target_tags = concat(["airgap-jump"], keys(local.instances))
}

resource google_compute_firewall "jump_to_clusters" {
  name    = "${var.nameprefix}-jump-to-clusters"
  network = google_compute_network.airgap_network.self_link
  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports = ["22"]
  }

  target_tags = keys(local.instances)
  source_tags = ["airgap-jump"]
}

resource google_compute_firewall "ingress_to_staging" {
  name    = "${var.nameprefix}-ingress-to-staging"
  network = google_compute_network.airgap_network.self_link
  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports = [22, 32000, 8800, 8080, 80, 443, 8443]
  }

  target_tags = ["staging-cluster", "staging-registry"]
}
