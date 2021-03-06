/**
 * Copyright 2018 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


# gcloud auth application-default login
provider "google" {
  version = "~> 3.14.0"
  region  = var.region
  # credentials = file("/xxxxx/xxxx/xxxx/account.json")
}

resource "google_service_account" "compute_engine_service_account" {
  account_id   = var.compute_engine_service_account
  display_name = "GKE Compuete Engine Service Account"
  project = var.project_id
}

variable "saroles" {
  description = "Map from availability zone to the number that should be used for each availability zone's subnet"
  default     = {
    "roles/compute.viewer" = 1
    "roles/container.clusterAdmin" = 2
    "roles/container.developer" = 3
    "roles/iam.serviceAccountAdmin" = 4
    "roles/iam.serviceAccountUser" = 5
    "roles/resourcemanager.projectIamAdmin" = 6
  }
}

resource "google_project_iam_binding" "saroles" {
  for_each = var.saroles
  project = var.project_id
  role    =each.key

  members = [
    "serviceAccount:${google_service_account.compute_engine_service_account.email}",
  ]
}

resource "google_kms_crypto_key_iam_binding" "gke_crypto_key" {
  crypto_key_id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.key_ring_name}/cryptoKeys/${var.key_name_gke}"
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.compute_engine_service_account.email}",
    "serviceAccount:service-${var.project_number}@compute-system.iam.gserviceaccount.com",
    "serviceAccount:service-${var.project_number}@container-engine-robot.iam.gserviceaccount.com",

  ]
}
resource "google_kms_crypto_key_iam_binding" "boot_disk_kms_key" {
  crypto_key_id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.key_ring_name}/cryptoKeys/${var.boot_disk_kms_key}"
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.compute_engine_service_account.email}",
    "serviceAccount:service-${var.project_number}@compute-system.iam.gserviceaccount.com",
    "serviceAccount:service-${var.project_number}@container-engine-robot.iam.gserviceaccount.com",

  ]
}

// Create a network for GKE
resource "google_compute_network" "network" {
  name                    = var.network
  project                 = var.project_id
  auto_create_subnetworks = false
}

// Create subnets
resource "google_compute_subnetwork" "subnetwork" {
  name          = var.subnetwork
  project       = var.project_id
  network       = google_compute_network.network.self_link
  region        = var.region
  ip_cidr_range = "192.168.0.0/24"

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = var.ip_range_pods
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = var.ip_range_services
    ip_cidr_range = "10.2.0.0/20"
  }
}

data "google_compute_subnetwork" "subnetwork" {
  name    = var.subnetwork
  project = var.project_id
  region  = var.region
  # ip_cidr_range="192.168.0.0/24"
}

resource "google_compute_firewall" "port-22-443-80-8080-8443" {
  name    = "${var.network}-port-22-443-80-8080-8443"
  project= var.project_id
  network = google_compute_network.network.self_link

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "8080", "443", "8443"]
  }
  source_ranges =["0.0.0.0/0"]
}



module "gke" {
  # https://github.com/terraform-google-modules/terraform-google-kubernetes-engine.git
  # source                    = "../terraform-google-kubernetes-engine/modules/private-cluster/"
  # source                    = "git::https://github.com/terraform-google-modules/terraform-google-kubernetes-engine.git//modules/beta-private-cluster?ref=release-v8.2.0"
  source                    = "git::https://github.com/dmilan77/terraform-google-kubernetes-engine.git//modules/beta-private-cluster"
  project_id                = var.project_id
  name                      = "${var.gke_cluster_name}"
  regional                  = false
  region                    = var.region
  zones                     = var.zones
  network                   = var.network
  subnetwork                = var.subnetwork
  ip_range_pods             = var.ip_range_pods
  ip_range_services         = var.ip_range_services
  create_service_account    = false
  service_account           = "${google_service_account.compute_engine_service_account.email}"
  enable_private_endpoint   = true
  enable_private_nodes      = true
  istio                                    = false
  master_ipv4_cidr_block    = "172.16.0.0/28"
  default_max_pods_per_node = 20
  remove_default_node_pool  = true
  network_policy                     = true
  network_policy_provider       = "CALICO"
  node_metadata                      = "GKE_METADATA_SERVER"
  identity_namespace              = "${var.project_id}.svc.id.goog"

  node_pools = [
    {
      name              = "pool-01"
      machine_type      = "n1-standard-2"
      min_count         = 1
      max_count         = 3
      local_ssd_count   = 0
      disk_size_gb      = 30
      disk_type         = "pd-standard"
      image_type        = "COS"
      auto_repair       = true
      auto_upgrade      = true
      preemptible       = false
      service_account   = "${google_service_account.compute_engine_service_account.email}"
      preemptible       = false
      max_pods_per_node = 12
      boot-disk-kms-key = "${google_kms_crypto_key_iam_binding.boot_disk_kms_key.crypto_key_id}"
    },
  ]
  node_pools_labels = {
    all = {}

    default-node-pool = {
      default-node-pool = true
    }
  }
  node_pools_tags = {
    all = []

    default-node-pool = [
      "default-node-pool",
    ]
  }
database_encryption = [
  {
    state="ENCRYPTED"
    key_name="${google_kms_crypto_key_iam_binding.gke_crypto_key.crypto_key_id}"
  }
]

  master_authorized_networks = [
    {
      cidr_block   = google_compute_subnetwork.subnetwork.ip_cidr_range
      display_name = "VPC"
    },
  ]

}
# module "workload_identity" {
#   # source                    = "git::https://github.com/terraform-google-modules/terraform-google-kubernetes-engine.git//modules/workload-identity?ref=release-v8.2.0"
#   source                    = "git::https://github.com/dmilan77/terraform-google-kubernetes-engine.git//modules/workload-identity"
#   project_id          = var.project_id
#   name                = "iden-${module.gke.name}"
#   namespace           = "default"
#   use_existing_k8s_sa = false
# }
resource "google_compute_instance" "k8bastion" {
  name         = var.bastion_host_name
  project         = var.project_id
  machine_type = "n1-standard-1"
  zone         = var.zones[0]

  tags = ["foo", "bar"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }

  // Local SSD disk
  scratch_disk {
    interface = "SCSI"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnetwork.self_link

    access_config {
      // Ephemeral IP
    }
  }

  metadata = {
    foo = "bar"
  }

  metadata_startup_script = file("startup.sh")

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }
}
data "google_client_config" "default" {
}
