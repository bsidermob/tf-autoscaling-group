# Need to specify AWS access keys
variable "access_key" {
  default = "FILL_IN"
}

variable "secret_key" {
  default = "FILL_IN"
}

variable public_key {
  description = "SSH public key"
  default = "~/.ssh/id_rsa.pub"
}

variable private_key {
  description = "SSH private key"
  default = "~/.ssh/id_rsa"
}

variable "key_name" {
  description = "Desired name of AWS key pair"
  default = "Mike's Key"
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "ap-southeast-2"
}

variable "mysql_user" {
  default = "testdb"
}

variable "mysql_password" {
  default = "testdb123"
}

# Ubuntu Server 16.04 LTS
variable "aws_amis" {
  default = {
    us-west-1 = "ami-07585467"
    ap-southeast-2 = "ami-0789a5fb42dcccc10"
  }
}
