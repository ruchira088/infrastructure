module "k3s_node" {
  source            = "../modules/k3s-server"
  availability_zone = var.availability_zone
  ec2_name          = "k3s-server"
  volume_size       = 100
  instance_type     = "t3a.large"

  init_script = <<-EOF
    #!/usr/bin/env bash

    curl -sfL https://get.k3s.io | sh - && \
    mkdir -p ~/.kube && \
    sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config && \
    sudo chmod 600 ~/.kube/config && \
    echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc && \
    echo "alias k='kubectl'" >> ~/.bashrc
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
