variable "subscription" {}
variable "tenant" {}
variable "location" {}
variable "resource_group" {}

variable "app_reg_name" {
  description = "Application service principal"
}

variable "principal_roles" {}

variable "vnet_name" {}

variable "vnet_cidr" {}

variable "master_subnet_name" {}

variable "master_subnet_cidr" {}

variable "worker_subnet_name" {}

variable "worker_subnet_cidr" {}

variable "number_of_master_nodes" {}

variable "number_of_worker_nodes" {}
