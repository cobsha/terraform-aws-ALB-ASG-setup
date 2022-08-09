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