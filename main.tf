######
# Access details
######

provider "aws" {
  region = "${var.aws_region}"
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
}

# Key pair for AWS VMs

resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key)}"
}

######
# VPC
######

# Create a VPC

resource "aws_vpc" "web" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
}

# Create an internet gateway

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.web.id}"
}

# Grant VPC internet access

resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.web.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create subnets

resource "aws_subnet" "web-aza" {
  vpc_id                  = "${aws_vpc.web.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "${var.aws_region}a"
}

resource "aws_subnet" "web-azb" {
  vpc_id                  = "${aws_vpc.web.id}"
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone = "${var.aws_region}b"
}

resource "aws_subnet" "database-aza" {
  vpc_id                  = "${aws_vpc.web.id}"
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = false
  availability_zone = "${var.aws_region}a"
}

resource "aws_subnet" "database-azb" {
  vpc_id                  = "${aws_vpc.web.id}"
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = false
  availability_zone = "${var.aws_region}b"
}

######
# ELB
######

# Create ELB

resource "aws_elb" "web" {
  name = "web-elb"

  subnets         = ["${aws_subnet.web-aza.id}", "${aws_subnet.web-azb.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  # instances       = ["${aws_instance.web.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
}

# Create security group for ELB

resource "aws_security_group" "elb" {
  name        = "web-elb"
  description = "Used for web server"
  vpc_id      = "${aws_vpc.web.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
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

######
# EC2
######

# The dependencies should be baked into an AMI image
# to speed up boot up but for test purposes a launch
# configuration would suffice too

# Create launch configuration

resource "aws_launch_configuration" "webcluster" {
  image_id = "${lookup(var.aws_amis, var.aws_region)}"
  instance_type = "t2.micro"
  security_groups = ["${aws_security_group.web.id}"]
  key_name = "${aws_key_pair.auth.id}"
  # user data formatting is off because it passes spaces which prevents the script from running upon launch
  # consider putting into an external file
  user_data = "${file("conf/userdata.sh")}"

  lifecycle {
  create_before_destroy = true
  }
}


# Create autoscaling group

resource "aws_autoscaling_group" "scalinggroup" {
  launch_configuration = "${aws_launch_configuration.webcluster.name}"
  availability_zones = ["${aws_subnet.web-aza.availability_zone}", "${aws_subnet.web-azb.availability_zone}"]
  vpc_zone_identifier = ["${aws_subnet.web-aza.id}", "${aws_subnet.web-azb.id}"]
  # cant' use self-reference, so using ELB AZs
  # the logic is 1 subnet = 1 AZ
  # ASG will maintain equal number of instances per zone
  min_size = "${length("${aws_elb.web.subnets}") * 2}"
  max_size = 8
  enabled_metrics = ["GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances", "GroupTotalInstances"]
  metrics_granularity = "1Minute"
  load_balancers = ["${aws_elb.web.id}"]
  health_check_type = "ELB"
  tag {
    key = "Name"
    value = "Web-autoscaling-group"
    propagate_at_launch = true
  }
  #depends_on = ["aws_db_instance.database"]
}

# Create autoscaling policy

# Ramp up

resource "aws_autoscaling_policy" "autopolicy-up" {
  name = "autoplicy-up"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = "${aws_autoscaling_group.scalinggroup.name}"
}

# Create Cloudwatch alarms

resource "aws_cloudwatch_metric_alarm" "cpualarm" {
  alarm_name = "cpu-high-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "60"

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.scalinggroup.name}"
  }

  alarm_description = "EC2 instance CPU utilization high"
  alarm_actions = ["${aws_autoscaling_policy.autopolicy-up.arn}"]
}

# Cool down

resource "aws_autoscaling_policy" "autopolicy-down" {
  name = "autoplicy-down"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = "${aws_autoscaling_group.scalinggroup.name}"
}

# Create Cloudwatch alarms

resource "aws_cloudwatch_metric_alarm" "cpualarm-down" {
  alarm_name = "cpu-low-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "10"

  dimensions {
  AutoScalingGroupName = "${aws_autoscaling_group.scalinggroup.name}"
  }

  alarm_description = "EC2 instance CPU utilization low"
  alarm_actions = ["${aws_autoscaling_policy.autopolicy-down.arn}"]
}

# Create security group for AWS VMs

resource "aws_security_group" "web" {
  name        = "admin access"
  description = "used to access machine services"
  vpc_id      = "${aws_vpc.web.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access within the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # HTTP access from elb
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# this is disabled to speed up provisioning
/*
######
# DB
######

resource "aws_db_instance" "database" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7.21"
  instance_class       = "db.t2.micro"
  name                 = "mydb"
  username             = "${var.mysql_user}"
  password             = "${var.mysql_password}"
  publicly_accessible      = false
  db_subnet_group_name = "${aws_db_subnet_group.db_subnet_group.name}"
  parameter_group_name = "default.mysql5.7"
  apply_immediately = true
  vpc_security_group_ids   = ["${aws_security_group.database_sec_group.id}"]
  skip_final_snapshot = true
}

*/

# Create DB subnet group

resource "aws_db_subnet_group" "db_subnet_group" {
  name          = "mysql-db-subnet-group"
  description   = "Allowed subnets for MySQL DB instance"
  subnet_ids    = ["${aws_subnet.database-aza.id}", "${aws_subnet.database-azb.id}"]
}

# Create DB security group

resource "aws_security_group" "database_sec_group" {
  name = "database_sec_group"
  description = "RDS MySQL server"
  vpc_id = "${aws_vpc.web.id}"

  # Only mysql in
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic.
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



######
# Auxiliary stuff
######

# Fetch autoscaling group IPs

data "aws_instances" "ip_addresses" {
  filter {
    name   = "tag:Name"
    # Have to figure out how not to hardcode tag name
    values = ["Web-autoscaling-group"]
  }
  depends_on = ["aws_autoscaling_group.scalinggroup"]
}
