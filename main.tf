############################
# Variables
############################
variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

# Windows path must use forward slashes
variable "ssh_pubkey" {
  type    = string
  default = "C:/Users/Vinicio Morillo/Downloads/IT 360-01 (B5) Cloud Integration/Final_Project/id_ed25519.pub"
}

variable "ansible_private_key_path" {
  type    = string
  default = "/mnt/c/Users/Vinicio Morillo/Downloads/IT 360-01 (B5) Cloud Integration/Final_Project/id_ed25519"
}

# --- AWS ---
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "aws_instance_type" {
  type    = string
  default = "t2.micro"
}
variable "aws_ami" {
  type    = string
  default = "ami-0bbdd8c17ed981ef9"
}

# --- GCP ---
variable "gcp_project" {
  type    = string
  default = "erudite-store-471004-j5"
}
variable "gcp_region" {
  type    = string
  default = "us-central1"
}
variable "gcp_zone" {
  type    = string
  default = "us-central1-a"
}
variable "gcp_machine" {
  type    = string
  default = "e2-micro"
}

############################
# Providers
############################
provider "aws" {
  region  = var.aws_region
  profile = "default"
}

provider "google" {
  project     = var.gcp_project
  region      = var.gcp_region
  zone        = var.gcp_zone
  credentials = file("${path.module}/erudite-store-471004-j5-875e9c26ef35.json")
}

############################
# AWS
############################
data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "web_sg" {
  name        = "it360-web-sg"
  description = "Allow SSH/HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "vm_key" {
  key_name   = "it360-aws-key"
  public_key = file(var.ssh_pubkey)
}

resource "aws_instance" "server" {
  ami                         = var.aws_ami
  instance_type               = var.aws_instance_type
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = aws_key_pair.vm_key.key_name
  associate_public_ip_address = true
  tags = { Name = "it360-aws" }
}

############################
# GCP
############################
resource "google_compute_firewall" "allow_ssh_http" {
  name    = "it360-allow-ssh-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["it360-web"]
}

locals {
  gcp_ssh_entry = "${var.ssh_username}:${chomp(file(var.ssh_pubkey))}"
}

resource "google_compute_instance" "gcp_server" {
  name         = "it360-gcp"
  machine_type = var.gcp_machine
  zone         = var.gcp_zone
  tags         = ["it360-web"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata = {
    ssh-keys = local.gcp_ssh_entry
  }

  depends_on = [google_compute_firewall.allow_ssh_http]
}

############################
# Outputs
############################
output "AWS_PUBLIC_IP" {
  value       = aws_instance.server.public_ip
  description = "AWS EC2 public IP"
}

output "AWS_SSH" {
  value = "ssh -i ${var.ansible_private_key_path} ${var.ssh_username}@${aws_instance.server.public_ip}"
}

output "GCP_PUBLIC_IP" {
  value       = google_compute_instance.gcp_server.network_interface[0].access_config[0].nat_ip
  description = "GCP external IP"
}

output "GCP_SSH" {
  value = "ssh -i ${var.ansible_private_key_path} ${var.ssh_username}@${google_compute_instance.gcp_server.network_interface[0].access_config[0].nat_ip}"
}

############################
# Write inventory.ini with BOTH hosts
############################
locals {
  aws_ip = try(aws_instance.server.public_ip, null)
  gcp_ip = google_compute_instance.gcp_server.network_interface[0].access_config[0].nat_ip

  host_lines = compact([
    local.aws_ip != null ? "${local.aws_ip} ansible_user=${var.ssh_username} ansible_ssh_private_key_file=${var.ansible_private_key_path}" : null,
    "${local.gcp_ip} ansible_user=${var.ssh_username} ansible_ssh_private_key_file= #${var.ansible_private_key_path}"
  ])
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.ini"
  content  = <<-EOT
  [web]
  ${join("\n", local.host_lines)}

  [all:vars]
  ansible_python_interpreter=/usr/bin/python3
  EOT

  depends_on = [
    aws_instance.server,
    google_compute_instance.gcp_server
  ]
}
