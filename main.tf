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

resource "aws_key_pair" "key" {

  key_name   = "${var.project}-key"
  public_key = file("key.pub")
  tags = {

    name = "${var.project}-key"
    project = var.project
  }
}

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