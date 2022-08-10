resource "random_uuid" "k3s_token" {}

module "k3s_server_1" {
  source            = "./modules/k3s-server"
  availability_zone = "ap-southeast-2a"
  ec2_name          = "k3s-server-1"

  init_script = <<-EOF
    #!/usr/bin/env bash

    curl -sfL https://get.k3s.io | K3S_NODE_NAME=k3s-1 K3S_TOKEN=${random_uuid.k3s_token.result} \
      sh -s - server --cluster-init

  EOF
}

module "k3s_server_2" {
  source            = "./modules/k3s-server"
  availability_zone = "ap-southeast-2b"
  ec2_name          = "k3s-server-2"

  init_script = <<-EOF
    #!/usr/bin/env bash

    curl -sfL https://get.k3s.io | K3S_NODE_NAME=k3s-2 K3S_TOKEN=${random_uuid.k3s_token.result} \
      sh -s - server --server https://${module.k3s_server_1.private_ip}:6443

  EOF

  depends_on = [
    module.k3s_server_1
  ]
}

module "k3s_server_3" {
  source            = "./modules/k3s-server"
  availability_zone = "ap-southeast-2c"
  ec2_name          = "k3s-server-3"

  init_script = <<-EOF
    #!/usr/bin/env bash

    curl -sfL https://get.k3s.io | K3S_NODE_NAME=k3s-3 K3S_TOKEN=${random_uuid.k3s_token.result} \
      sh -s - server --server https://${module.k3s_server_1.private_ip}:6443

  EOF

  depends_on = [
    module.k3s_server_1
  ]
}

data "aws_vpc" "vpc" {}

resource "aws_lb_target_group" "k3s_http_target_group" {
  name        = "k3s-http-target-group"
  port        = 80
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.vpc.id
}

resource "aws_lb_target_group_attachment" "http_target_group_attachment_1" {
  target_group_arn = aws_lb_target_group.k3s_http_target_group.arn
  target_id        = module.k3s_server_1.id
}

resource "aws_lb_target_group_attachment" "http_target_group_attachment_2" {
  target_group_arn = aws_lb_target_group.k3s_http_target_group.arn
  target_id        = module.k3s_server_2.id
}

resource "aws_lb_target_group_attachment" "http_target_group_attachment_3" {
  target_group_arn = aws_lb_target_group.k3s_http_target_group.arn
  target_id        = module.k3s_server_3.id
}

resource "aws_lb_target_group" "k3s_https_target_group" {
  name        = "k3s-https-target-group"
  port        = 443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.vpc.id
}

resource "aws_lb_target_group_attachment" "https_target_group_attachment_1" {
  target_group_arn = aws_lb_target_group.k3s_https_target_group.arn
  target_id        = module.k3s_server_1.id
}

resource "aws_lb_target_group_attachment" "https_target_group_attachment_2" {
  target_group_arn = aws_lb_target_group.k3s_https_target_group.arn
  target_id        = module.k3s_server_2.id
}

resource "aws_lb_target_group_attachment" "https_target_group_attachment_3" {
  target_group_arn = aws_lb_target_group.k3s_https_target_group.arn
  target_id        = module.k3s_server_3.id
}

resource "aws_lb_target_group" "k3s_admin_port_target_group" {
  name        = "k3s-admin-port-target-group"
  port        = 6443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.vpc.id
}

resource "aws_lb_target_group_attachment" "admin_port_target_group_attachment_1" {
  target_group_arn = aws_lb_target_group.k3s_admin_port_target_group.arn
  target_id        = module.k3s_server_1.id
}

resource "aws_lb_target_group_attachment" "admin_port_target_group_attachment_2" {
  target_group_arn = aws_lb_target_group.k3s_admin_port_target_group.arn
  target_id        = module.k3s_server_2.id
}

resource "aws_lb_target_group_attachment" "admin_port_target_group_attachment_3" {
  target_group_arn = aws_lb_target_group.k3s_admin_port_target_group.arn
  target_id        = module.k3s_server_3.id
}

data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = {
    Type = "public"
  }
}

resource "aws_lb" "k3s_lb" {
  name               = "k3s-lb"
  internal           = false
  load_balancer_type = "network"

  subnets = data.aws_subnets.public_subnets.ids
}

resource "aws_lb_listener" "http_lb_listener" {
  load_balancer_arn = aws_lb.k3s_lb.arn
  protocol          = "TCP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s_http_target_group.arn
  }
}

resource "aws_lb_listener" "https_lb_listener" {
  load_balancer_arn = aws_lb.k3s_lb.arn
  protocol          = "TCP"
  port              = 443

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s_https_target_group.arn
  }
}

resource "aws_lb_listener" "admin_port_lb_listener" {
  load_balancer_arn = aws_lb.k3s_lb.arn
  protocol          = "TCP"
  port              = 6443

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s_admin_port_target_group.arn
  }
}

data "aws_route53_zone" "ruchij_com" {
  name = "ruchij.com"
}

resource "aws_route53_record" "star_dev_ruchij_com" {
  name    = "*.dev.ruchij.com"
  type    = "A"
  zone_id = data.aws_route53_zone.ruchij_com.zone_id

  alias {
    name                   = aws_lb.k3s_lb.dns_name
    zone_id                = aws_lb.k3s_lb.zone_id
    evaluate_target_health = true
  }
}