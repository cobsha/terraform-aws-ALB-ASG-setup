# AWS ALB-ASG Setup using Terraform

![Untitled Diagram](https://user-images.githubusercontent.com/71638921/183583769-c7332ec0-12f2-4277-a9cd-e0546fa2af53.jpg)


This guide walk you through on how to set up Application LoadBalancer with Auto Scaling Group using Terraform.


Terraform is an open source Infrastructure as Code tool used to provision Infrastructure and resources. We can automate major cloud platforms like AWS, Azure or GCP using terraform.

### What is Application Load Balancer?

Application load balancer is one of the common load balancer used in AWS,  It works at the seventh layer of the OSI model, the application layer. We can add and remove targets from our load balancer as per our needs without affecting the flow of requests to the application. Application Load Balancer supports for path-based routing: forward requests based on the URL in the request, host-based routing: forward requests based on the host field in the HTTP header, routing based on fields in the request, registering targets by IP address: targets outside the VPC for the load balancer can also be added. These are a few of the benefits of using the Application Load Balancer.

### what is Auto Scaling Group?

An Auto Scaling group contains a collection of Amazon EC2 instances that are treated as a logical grouping for the purposes of automatic scaling and management. It maintains this number of instances by performing periodic health checks on the instances in the group.

## Prerequsites

* An AWS Account with an IAM user which has programmatic access and VPC and Instance level access (As a best practice you can attache role to an EC2 instance)
* Teraform Installed machine, you can refer official doc. https://www.terraform.io/downloads
* A domain name hosted in route53
* A TLS Certificate from ACM

## Setup

You need to have an AMI of an application instance inorder to create a launch template for Autoscaling group, so follow the below step to create an AMI from an instance.

<img src="https://user-images.githubusercontent.com/71638921/183569237-3de7cc6c-4092-49e9-9007-92bcff6cdace.jpg" width="800" height="450">

<img src="https://user-images.githubusercontent.com/71638921/183569506-6a3c83e2-0ed5-423a-9b9a-843dd955b1f3.jpg" width="800" height="450">

<img src="https://user-images.githubusercontent.com/71638921/183569569-d7bebbaf-ddc7-435e-bcc1-6941c83eaff8.jpg" width="800" height="450">

You can give a tag, it is an optional.

<img src="https://user-images.githubusercontent.com/71638921/183569643-3fa5a181-c869-49c3-a543-2e962ca90858.jpg" width="800" height="450">


## Provider Configuration

```bash
 #provider.tf
 provider "aws" {

  region = var.region
  access_key = "Enter Your Access key"
  secret_key = "Enter your secret key"   
}
```
When you use IAM role you don't have to mention access and secret key.

We need to initialize provider after configuring it in the file provider.tf. use below commands to initialize.
<img src="https://user-images.githubusercontent.com/71638921/182102656-8bede63a-1557-44da-b4b3-74e6ff23d44f.png" width="600" height="300">

## Variable Declarations


```bash
variable "region" {

    default = "ap-south-1"
}

variable "project" {

    default = "zomato"
}

variable "env" {
    
    type = list
    default = ["prod", "dev"] ##you need to mention your subdomain here instead of "prod" and "dev" as a list.
}

variable "domain" {

    default = "cobbtech.site"
}

variable "instance_type" {

    default = "t2.micro"
}
```

## Datasource

It's used to retrieve information about the resources in the current infra

```bash
data "aws_vpc" "default" {
  
  default = true
}

data "aws_subnets" "default" {

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_acm_certificate" "tls" {
  domain      = var.domain
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

data "aws_ami" "ami" {

  count = 2
  most_recent      = true
  owners           = ["self"]

  filter {
    name   = "name"
    values = ["${var.env[count.index]}-version*"]
  }

}

data "aws_availability_zones" "available" {
  
  state = "available"
}

data "aws_route53_zone" "r53" {
  
  name         = "cobbtech.site."
  private_zone = false
}
```
## Output

Necessary Ouput

```bash
output "vpc" {
    value = data.aws_vpc.default.id
}

output "subnet" {

    value = data.aws_subnets.default
}

output "r53_records" {

    value = aws_route53_record.record[*].name

}
```

## Main Configuration

## Application LoadBalancer Setup

### Security Group

```bash
resource "aws_security_group" "alb_sg" {

  name_prefix = "${var.project}-sg-"
  description = "Allow TLS and HTTP inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description      = "TLS traaffic from outside"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTP traffic from outside"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  
  lifecycle {

    create_before_destroy = true
  }

  tags = {
    Name = "${var.project}-alb-sg"
    project = var.project
  }
}

``
### Target Group

I create 2 target for my 2 subdomains.

```bash
resource "aws_lb_target_group" "tg" {
  
  count = 2
  name_prefix = "${var.env[count.index]}-"
  target_type = "instance"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  deregistration_delay = 120
  health_check {
    
    protocol = "HTTP"
    path = "/"
    matcher = 200
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
  tags = {

    project = var.project
    env = "${var.env[count.index]}"
  }
  lifecycle {

    create_before_destroy = true
  }
}
```

### LoadBalancer

```bash
resource "aws_lb" "lb" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-04a8aaa4c987841c1"]
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "${var.project}-alb"
  }
}

```
### Listeners and Listeners rules

```bash
resource "aws_lb_listener" "httpslistener" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.tls.arn

  default_action {

    type = "fixed-response"

    fixed_response {
      content_type = "text/html"
      message_body = "<h1>Site not found!</h1>"
      status_code  = "503"
    }
  }
  tags = {

    project = var.project
  }
}

resource "aws_lb_listener" "httplistener" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
```

```bash
resource "aws_lb_listener_rule" "rule" {
  
  count = 2
  listener_arn = aws_lb_listener.httpslistener.arn
  priority     = "${count.index +1}"

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg[count.index].arn
  }

  condition {
    host_header {
      values = ["${var.env[count.index]}.${var.domain}"]
    }
  }
}
```
## Autoscaling Group Setup

### Launch Template

I create 2 Security Group and 1 key pair for my launch template configuration.

```bash
resource "aws_security_group" "instance" {

  count =2
  name_prefix = "${var.env[count.index]}-sg-"
  description = "Allow HTTP traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description      = "HTTP traffic from outside"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "SSH traffic from outside"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  
  lifecycle {

    create_before_destroy = true
  }

  tags = {
    Name = "${var.project}-${var.env[count.index]}-alb-sg"
    project = var.project
    env = var.env[count.index]
  }
}

```
We need to create a keypair locally from our machine and upload to the code

<img src="https://user-images.githubusercontent.com/71638921/182206944-574b5537-872f-4096-909d-5a96e40f9be0.png" width="600" height="300">

```bash
resource "aws_key_pair" "key" {

  key_name   = "${var.project}-key"
  public_key = file("key.pub")
  tags = {

    name = "${var.project}-key"
    project = var.project
  }
}
```
launch template

```bash
resource "aws_launch_template" "tmplt" {

  count = 2
  name_prefix   = "${var.env[count.index]}-"
  image_id      = data.aws_ami.ami[count.index].image_id
  instance_type = var.instance_type
  key_name = aws_key_pair.key.key_name
  vpc_security_group_ids = [aws_security_group.instance[count.index].id]
  lifecycle {

    create_before_destroy = true
  }
}
```

### Auto Scaling Group

```bash
resource "aws_autoscaling_group" "asg" {

  count = 2
  name_prefix = "${var.env[count.index]}-"
  availability_zones = data.aws_availability_zones.available.names
  desired_capacity   = 2
  max_size           = 2
  min_size           = 2
  default_cooldown = 180
  health_check_grace_period = 120
  health_check_type = "EC2"
  target_group_arns = [aws_lb_target_group.tg[count.index].arn]

  launch_template {

    id      = aws_launch_template.tmplt[count.index].id
    version = "$Latest"
  }

tag {

    key = "Name"
    value = "${var.project}-${var.env[count.index]}"
    propagate_at_launch = true
}
}
```
## Adding an alias Record for ALB endpoint in Route53

```bash
resource "aws_route53_record" "record" {

  count = 2
  zone_id = data.aws_route53_zone.r53.zone_id
  name    = "${var.env[count.index]}.${data.aws_route53_zone.r53.name}"
  type    = "A"

  alias {
    name                   = aws_lb.lb.dns_name
    zone_id                = aws_lb.lb.zone_id
    evaluate_target_health = true
  }
}
```

After all this configuration we need to validate above code

<img src="https://user-images.githubusercontent.com/71638921/183581282-44bff48e-b7fe-4077-b0a5-c705dc275a6f.png" width="300" height="100">


As a final step we can apply the code if there is no errors found in validation step (You can also check plan befor apply using the command "terraform apply")

<img src="https://user-images.githubusercontent.com/71638921/183581323-2510c300-bba7-4572-bb69-fbf9a273aaee.png" width="600" height="300">


<img src="https://user-images.githubusercontent.com/71638921/183581355-e7729d81-8c0a-47d8-bfb8-4d71c223fbeb.png" width="600" height="300">


## Conclusion

We have created Application load balancer with Autoscaling Group for 2 subdomains successfully
