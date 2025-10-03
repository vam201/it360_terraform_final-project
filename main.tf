provider "aws" {
  region  = "us-east-1"
  profile = "default"
}

# Use the default VPC explicitly (avoids EC2-Classic issues)
data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "web_sg" {
  name        = "it360-web-sg"
  description = "Allow SSH (22) and HTTP (80) from anywhere"
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

# Key pair from your local public key
resource "aws_key_pair" "vm_key" {
  key_name   = "it360-aws-key"
  public_key = file("${path.module}/id_ed25519.pub")
}

resource "aws_instance" "server" {
  ami                         = "ami-0bbdd8c17ed981ef9"
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = aws_key_pair.vm_key.key_name
  associate_public_ip_address = true

  tags = { Name = "it360-web" }
}

# OUTPUTS
output "instance_id" { value = aws_instance.server.id }
output "PUBLIC_IP" { value = aws_instance.server.public_ip }
output "PUBLIC_DNS" { value = aws_instance.server.public_dns }
output "INSTANCE_STATE" { value = aws_instance.server.instance_state }
output "SSH_COMMAND" {
  value = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.server.public_ip}"
}
