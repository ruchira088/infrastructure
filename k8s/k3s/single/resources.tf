module "k3s_node" {
  source            = "../modules/k3s-server"
  availability_zone = var.availability_zone
  ec2_name          = "k3s-server"
  volume_size       = 100

  init_script = <<-EOF
    #!/usr/bin/env bash

    mkdir -p /mnt/data/videos && mkdir -p /mnt/data/images

    curl -sfL https://get.k3s.io | sh -

  EOF
}

data "aws_route53_zone" "ruchij_com" {
  name = "ruchij.com"
}

resource "aws_route53_record" "dev_ruchij_com" {
  name    = "dev.ruchij.com"
  type    = "A"
  zone_id = data.aws_route53_zone.ruchij_com.zone_id
  ttl     = 300

  records = [module.k3s_node.public_ip]
}

resource "aws_route53_record" "star_dev_ruchij_com" {
  name    = "*.dev.ruchij.com"
  type    = "CNAME"
  zone_id = data.aws_route53_zone.ruchij_com.zone_id
  ttl     = 300

  records = ["dev.ruchij.com"]
}
