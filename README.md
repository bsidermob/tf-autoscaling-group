# Terraform autoscaling group

This spins up an autoscaling group in AWS with the help of Terraform.

The instances can also do an HTTP to HTTPS redirect but a cert is required
for that on the ELB, hence it's disabled for now but can easily be enabled
by uncommenting lines in the Apache config and adding the cert to the ELB.

Usage:
terraform init
terraform apply