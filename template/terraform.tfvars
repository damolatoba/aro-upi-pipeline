subscription 			= "549cf74a-fcb0-49d2-8a63-968ea8b2b1f8"
tenant 			= "84cc859e-d165-4b0e-8b05-b47b775371e7"
location = "EastUS"
resource_group = "aro-upi-rg"

#Vnet details
vnet_name			= "aro-vnet"
vnet_cidr			= "10.0.0.0/22"
master_subnet_name		= "aro-master-subnet"
master_subnet_cidr		= "10.0.0.0/23"
worker_subnet_name		= "aro-worker-subnet"
worker_subnet_cidr		= "10.0.2.0/23"

#Nodes
number_of_master_nodes = "3"

number_of_worker_nodes = "3"




app_reg_name = "aro-sp"
principal_roles = [
  {
    role = "Contributor"
  },
  {
    role = "User Access Administrator"
  }
]
