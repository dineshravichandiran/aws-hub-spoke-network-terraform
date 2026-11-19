# A tiny instance that serves one line of text on port 8080. It exists only so the network can be
# tested: curl between spokes, resolve private names, run Reachability Analyzer between instances.
# No SSH, no key pair, no public IP. Access is through Systems Manager Session Manager.

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "Probe: 8080 and ping from the allowed private ranges only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  count = length(var.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "Probe web server"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = var.allowed_cidrs[count.index]
}

resource "aws_vpc_security_group_ingress_rule" "icmp" {
  count = length(var.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "Ping"
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.allowed_cidrs[count.index]
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS out: Session Manager and package mirrors"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "probe_out" {
  count = length(var.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "Reach other probes on 8080"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = var.allowed_cidrs[count.index]
}

resource "aws_vpc_security_group_egress_rule" "ping_out" {
  count = length(var.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "Ping other probes"
  ip_protocol       = "icmp"
  from_port         = -1
  to_port           = -1
  cidr_ipv4         = var.allowed_cidrs[count.index]
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = var.name
  role = aws_iam_role.this.name

  tags = var.tags
}

resource "aws_instance" "this" {
  ami                    = nonsensitive(data.aws_ssm_parameter.ami.value)
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  ebs_optimized               = true
  monitoring                  = true
  associate_public_ip_address = false

  # Version 2 of the metadata service only: blocks the classic SSRF credential theft path.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  user_data = <<-EOT
    #!/bin/bash
    set -eu
    mkdir -p /srv/www
    echo "hello from ${var.name}" > /srv/www/index.html
    cat > /etc/systemd/system/probe.service <<'UNIT'
    [Unit]
    Description=Probe web server
    After=network.target

    [Service]
    WorkingDirectory=/srv/www
    ExecStart=/usr/bin/python3 -m http.server 8080
    Restart=always

    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable --now probe.service
  EOT

  user_data_replace_on_change = true

  tags = merge(var.tags, { Name = var.name })
}
