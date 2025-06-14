##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  # access_key and secret_key are removed for security; use environment variables or shared credentials file
  region = "us-east-2"
}

##################################################################################
# DATA
##################################################################################

data "aws_ssm_parameter" "amzn2_linux" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
resource "aws_vpc" "app" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id

}

# Creates a public subnet within the specified VPC.
# - cidr_block: The CIDR block for the subnet.
# - vpc_id: The ID of the VPC to associate with this subnet.
# - map_public_ip_on_launch: Automatically assigns a public IP address to instances launched in this subnet.
resource "aws_subnet" "public_subnet1" {
  cidr_block              = "10.0.0.0/24"
  vpc_id                  = aws_vpc.app.id
  map_public_ip_on_launch = true

}

# ROUTING #
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }
}

resource "aws_route_table_association" "app_subnet1" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.app.id
}

# SECURITY GROUPS #
# Nginx security group 
resource "aws_security_group" "nginx_sg" {
  name   = "nginx_sg"
  vpc_id = aws_vpc.app.id

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # ssh access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# INSTANCES #
resource "aws_instance" "nginx1" {
  ami                    = nonsensitive(data.aws_ssm_parameter.amzn2_linux.value)
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public_subnet1.id
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_instance_profile.name
  key_name               = "my-ec2key" # Replace with the name of your key pair
  user_data              = <<EOF
#! /bin/bash
yum install -y httpd amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

sudo sed -i 's/"Interval": *[0-9]\+/"Interval": 300/' /etc/amazon/ssm/amazon-ssm-agent.json
sudo systemctl restart amazon-ssm-agent

sudo amazon-linux-extras install -y nginx1
sudo service nginx start
sudo rm /usr/share/nginx/html/index.html
echo '<html><head><title>Taco Team Server</title></head><body style=\"background-color:#1F778D\"><p style=\"text-align: center;\"><span style=\"color:#FFFFFF;\"><span style=\"font-size:28px;\">You did it! Have a &#127790;</span></span></p></body></html>' | sudo tee /usr/share/nginx/html/index.html
EOF

}

resource "aws_key_pair" "my_ec2key" {
  key_name   = "my-ec2key"
  public_key = file("./my-ec2key.pub")
}

resource "aws_iam_role" "ssm_role" {
  name = "AmazonEC2RoleforSSM"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "SSMInstanceProfile"
  role = aws_iam_role.ssm_role.name
}
/* 
# Creates an AWS Network Load Balancer (NLB) named "app-nlb".
# - Not internal (public-facing).
# - Associated with the specified public subnet.
# - Deletion protection is disabled.
# NETWORK LOAD BALANCER
resource "aws_lb" "app_nlb" {
  name                       = "app-nlb"
  internal                   = false
  load_balancer_type         = "network"
  subnets                    = [aws_subnet.public_subnet1.id]
  enable_deletion_protection = false
  security_groups            = [aws_security_group.nginx_sg.id]

  tags = {
    Name = "app-nlb"
  }
}

# -----------------------------------------------------------------------------
# Creates an AWS Network Load Balancer (NLB) target group for TCP traffic on port 80.
# Associates the target group with a VPC.
#
# Provisions an NLB listener on port 80 using the TCP protocol, forwarding traffic
# to the defined target group.
#
# Attaches an EC2 instance (nginx1) to the target group, registering it as a target
# on port 80.
#
# Resources:
# - aws_lb_target_group.app_nlb_tg: Target group for NLB.
# - aws_lb_listener.app_nlb_listener: Listener for NLB forwarding to the target group.
# - aws_lb_target_group_attachment.app_nlb_attachment: Attaches EC2 instance to the target group.
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "app_nlb_tg" {
  name     = "app-nlb-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.app.id

}

resource "aws_lb_listener" "app_nlb_listener" {
  load_balancer_arn = aws_lb.app_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_nlb_tg.arn
  }


}

# Attaches an EC2 instance (nginx1) to the specified Application Load Balancer (ALB) target group.
# - `target_group_arn`: ARN of the target group to attach the instance to.
# - `target_id`: ID of the EC2 instance to register as a target.
# - `port`: Port on which the target receives traffic from the load balancer.
resource "aws_lb_target_group_attachment" "app_nlb_attachment" {
  target_group_arn = aws_lb_target_group.app_nlb_tg.arn
  target_id        = aws_instance.nginx1.id
  port             = 80



}

 */