
output "amzn2_linux_ami" {
  value     = data.aws_ssm_parameter.amzn2_linux.value
  sensitive = true
}

output "nginx_instance_id" {
  value = aws_instance.nginx1.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.app.id
}

output "route_table_id" {
  value = aws_route_table.app.id
}

output "route_table_association_id" {
  value = aws_route_table_association.app_subnet1.id
}

output "nginx_security_group_id" {
  value = aws_security_group.nginx_sg.id
}

output "public_subnet_id" {
  value = aws_subnet.public_subnet1.id
}

output "vpc_id" {
  value = aws_vpc.app.id
}
/* 
output "nlb_dns_name" {
  description = "The DNS name of the Network Load Balancer."
  value       = aws_lb.app_nlb.dns_name
} */
