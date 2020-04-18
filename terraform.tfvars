project_id                                             =   "data-protection-01"
project_number                                   = "196167569517"
gke_cluster_name                               =   "dmilan-gke-01"
region                                                   =    "us-east1"
regional                                                =  false
zones                                                  = ["us-east1-b"]
network                                               =   "network-data-protection-01"
subnetwork                                         =   "network-data-protection-01"
ip_range_pods                                    =   "pods"
ip_range_services                               =   "services"
compute_engine_service_account    =  "gke-admin-01"
key_ring_name                                    =  "gke-keyring-01"
key_name_gke                                     = "etcd-key-01"
key_name_disk                                    = "disk-key-01"