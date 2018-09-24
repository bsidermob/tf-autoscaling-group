# Elb DNS
output "elb_address" {
  value = "${aws_elb.web.dns_name}"
}

# List AWS EC2 DNS names
output "public_dns" {
  value = "${data.aws_instances.ip_addresses.public_ips}"
}

/*
# List MySQL hostname
output "mysql_host" {
  value = "${aws_db_instance.database.address}"
}

# List MySQL username
output "mysql_user" {
  sensitive = true
  value = "${var.mysql_user}"
}

# List MySQL password
output "mysql_password" {
  sensitive = true
  value = "${var.mysql_password}"
}
*/
