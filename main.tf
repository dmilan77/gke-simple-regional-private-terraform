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



provider "google" {
  version = "~> 3.14.0"
  region  = var.region
  credentials = file("~/.google/account.json")
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

resource "google_project_iam_binding" "computeviewer" {
  for_each = var.saroles
  project = var.project_id
  role    =each.key

  members = [
    "serviceAccount:${google_service_account.compute_engine_service_account.email}",
  ]
}



data "google_compute_subnetwork" "subnetwork" {
  name    = var.subnetwork
  project = var.project_id
  region  = var.region
}

module "gke" {
  # https://github.com/terraform-google-modules/terraform-google-kubernetes-engine.git
  # source                    = "../terraform-google-kubernetes-engine/modules/private-cluster/"
  source                    = "git::https://github.com/terraform-google-modules/terraform-google-kubernetes-engine.git//modules/private-cluster?ref=v8.1.0"
  project_id                = var.project_id
  name                      = "${var.gke_cluster_name}"
  regional                  = true
  region                    = var.region
  network                   = var.network
  subnetwork                = var.subnetwork
  ip_range_pods             = var.ip_range_pods
  ip_range_services         = var.ip_range_services
  create_service_account    = false
  service_account           = "${google_service_account.compute_engine_service_account.email}"
  enable_private_endpoint   = true
  enable_private_nodes      = true
  master_ipv4_cidr_block    = "172.16.0.0/28"
  default_max_pods_per_node = 20
  remove_default_node_pool  = true

  node_pools = [
    {
      name              = "pool-01"
      machine_type      = "n1-standard-2"
      min_count         = 1
      max_count         = 100
      local_ssd_count   = 0
      disk_size_gb      = 100
      disk_type         = "pd-standard"
      image_type        = "COS"
      auto_repair       = true
      auto_upgrade      = true
      service_account   = "${google_service_account.compute_engine_service_account.email}"
      preemptible       = false
      max_pods_per_node = 12
    },
  ]

  master_authorized_networks = [
    {
      cidr_block   = data.google_compute_subnetwork.subnetwork.ip_cidr_range
      display_name = "VPC"
    },
  ]
}

data "google_client_config" "default" {
}
