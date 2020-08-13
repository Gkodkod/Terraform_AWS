# Using Strings var
#  subnet_prefix = ["10.0.100.0/24", "10.10.200.0/24"]
# Using Object var
subnet_prefix = [{ cidr_block = "10.0.1.0/24", name = "prod_subnet" }, { cidr_block = "10.10.2.0/24", name = "dev_subnet" }]
nic_private_ips = "10.0.1.50"