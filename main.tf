# Configure the AWS Provider
provider "aws" {
#  version = "~> 3.0"  (optional)
  region  = "us-east-1"

# Static Credentials
# Warning:
# Hard-coding credentials into any Terraform configuration is not recommended, 
# and risks secret leakage should this file ever be committed to a public version control system.
  access_key = "AKIAJ72AQ4DEQJY4VOMQ"
  secret_key = "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"
}

# Will allow us to assign a value on - terraform apply or thru terraform.tfvars (latter is better)
variable "subnet_prefix" {
    description = "cidr block for the subnet"
    # default = 
    type = list 
}




# 0. setup access pairs (pem - openssl or ppk - putty )
# 1. Create vpc
resource "aws_vpc" "prod_vpc" {
  cidr_block = "10.0.0.0/16"
    tags = {
        Name = "production"
    }
}

resource "aws_vpc" "dev_vpc" {
  cidr_block = "10.10.0.0/16"
    tags = {
        Name = "dev"
    }
}
# 2. Create Internet Gateway (Be able to send traffic to internet)
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod_vpc.id

  tags = {
    Name = "prod_vpc"
  }
}

# 3. Create Custom Route Table (allows our subnet to getout to the internet)
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block    = "::/0"
    gateway_id         = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod"
  }
}
# 4. Create a subnet
resource "aws_subnet" "subnet-1" {
  vpc_id     = aws_vpc.prod_vpc.id
  # cidr_block = "10.0.1.0/24"
  cidr_block = var.subnet_prefix[0].cidr_block
  availability_zone = "us-east-1a"

  tags = {
    Name = var.subnet_prefix[0].name
  }
}

resource "aws_subnet" "subnet-2" {
  vpc_id     = aws_vpc.dev_vpc.id
  cidr_block = var.subnet_prefix[1].cidr_block

  tags = {
    Name = var.subnet_prefix[1].name
  }
}

output "subnet-1_cidr_block" {
    value = aws_subnet.subnet-1.cidr_block
}
output "subnet-2_cidr_block" {
    value = aws_subnet.subnet-2.cidr_block
}

# 5. Associate a subnet with a Route Table 
#   (Provides a resource to create an association between a route table and a subnet 
#       or a route table and an internet gateway or virtual private gateway.)
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# 6. Create Security Group to allow port 22,80,443 
#       (what kind of traffic is allowed to one of EC2 instances - for webserver 22-ssh, 80-http, 443-https)
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow wed inbound traffic"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description = "HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    ingress {
    description = "HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    ingress {
    description = "SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}
# 7. Create a Network interface with an ip in the subnet that was created in step 4

# Will allow us to assign a value on - terraform apply or thru terraform.tfvars (latter is better)
variable "nic_private_ips" {
    description = "private ips for webserver nic"
    type = string
}

resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  #private_ips     = ["10.0.1.50"]
  private_ips     = [var.nic_private_ips]
  security_groups = [aws_security_group.allow_web.id]

    #   attachment {
    #     instance     = "${aws_instance.test.id}"
    #     device_index = 1
    #   }
    ## SKIP ATTACHING TO DEVICE
}

output "nic_private_ips" {
    value = aws_network_interface.web-server-nic.private_ips
}

# 8. Assign an elastic IP to the Network interface created in step 7
#       Allows anyone on internet to access it
#  EIP may require IGW to exist prior to association. Use depends_on to set an explicit dependency on the IGW.
#  User depends_on to specify order of existance as a list in brackets (i.e. gw, vpc)

resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  //associate_with_private_ip = "10.0.1.50"
  associate_with_private_ip = var.nic_private_ips
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip" {
    value = aws_eip.one.associate_with_private_ip
}

# 9. Create ubuntu server and install / enable apache

resource "aws_instance" "web-server-instance" {
  ami           = "ami-0bcc094591f354be2"
  instance_type = "t3.micro"
  availability_zone = "us-east-1a"
  key_name = "main-key"

  network_interface {
      device_index = 0
      network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo Apache Web Server Started > /var/www/html/index.html'
                EOF
  tags = {
    Name = "ubuntu web-server"
  }
}

output "server_private_ip" {
    value = aws_instance.web-server-instance.private_ip
}
output "server_id" {
    value = aws_instance.web-server-instance.id
}




# resource "aws_vpc" "first_vpc" {
#   cidr_block = "10.0.0.0/16"
#     tags = {
#         Name = "production"
#     }
# }

# resource "aws_subnet" "subnet-1" {
#   vpc_id     = aws_vpc.first_vpc.id
#   cidr_block = "10.0.1.0/24"

#   tags = {
#     Name = "prod-subnet"
#   }
# }

# resource "aws_vpc" "second_vpc" {
#   cidr_block = "10.1.0.0/16"
#     tags = {
#         Name = "dev"
#     }
# }

# resource "aws_subnet" "subnet-2" {
#   vpc_id     = aws_vpc.second_vpc.id
#   cidr_block = "10.1.1.0/24"

#   tags = {
#     Name = "dev-subnet"
#   }
# }

# resource "aws_instance" "my-first-server" {
#   ami           = "ami-0bcc094591f354be2"
#   instance_type = "t3.micro"

#   tags = {
#     Name = "ubuntu"
#   }
# }

# terraform init  
#
# terraform plan
#
# terraform apply --auto-approve
#
# terraform destroy (all resources will be destroyed or comment out resource)
#
# terraform state
#
# terraform state list
#
# terraform state show aws_eip.one
# aws_eip.one:
# resource "aws_eip" "one" {
#     associate_with_private_ip = "10.0.1.50"
#     association_id            = "eipassoc-0052dec1002311f2f"
#     domain                    = "vpc"
#     id                        = "eipalloc-0a76f1068062e35fa"
#     network_interface         = "eni-056fc8ba3ed796850"
#     private_dns               = "ip-10-0-1-50.ec2.internal"
#     private_ip                = "10.0.1.50"
#     public_dns                = "ec2-54-91-96-247.compute-1.amazonaws.com"
#     public_ip                 = "54.91.96.247"
#     public_ipv4_pool          = "amazon"
#     vpc                       = true
# }
#
# terraform refresh (does not apply & will only print output)
#
# terraform output
#
# terraform destroy -target aws_instance.web-server-instance (only this resources will be destroyed)
#
# terraform apply -target aws_instance.web-server-instance
#
# terraform apply -var "subnet_prefix=10.0.1.0/24" 
#
# Better to use filename for vars - terraform.tfvars
#
# add a different filename rather than terraform.tfvars like so:
#   terraform apply -var-file second.tfvars 


# resource "<provider>_<resource_type>" "name" {
#     config options...
#     key = "value"
#     key2 = "another value"
# }

