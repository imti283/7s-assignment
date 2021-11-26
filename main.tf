###################################################
########      Local Variables         #############
###################################################
/*
Local Constant values
*/
locals {
  application = "7Sender"
  environment = "POC"
  api_flavor  = "t2.small"
  common_tags = {
    Application = "7Sender"
    ManagedBy   = "7s-DevOps-Terraform"
    Environment = "POC"
  }
}

###################################################
########       Security Group         #############
###################################################
/*
Security Group to be Assigned to EC2 Backend Servers,
Which needs to whitelist respective ELB on port 80
*/
resource "aws_security_group" "sevens_backend_sg" {
  name        = "SG-${local.application}-backend"
  description = "Security Group for ${local.application} ${local.environment} backend"
  vpc_id      = data.aws_vpc.default.id
  tags = merge(
    local.common_tags,
    {
      Name = "SG-${local.application}-backend"
    },
  )
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 80
    protocol        = "tcp"
    to_port         = 80
    security_groups = [aws_security_group.sevens_alb_sg.id]
    description     = "Allow connection from alb SG"
  }
}

resource "aws_security_group" "sevens_alb_sg" {
  name        = "SG-${local.application}-alb"
  description = "Security Group for ${local.application} ${local.environment} alb"
  vpc_id      = data.aws_vpc.default.id
  tags = merge(
    local.common_tags,
    {
      Name = "SG-${local.application}-alb"
    },
  )
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow connection from internet at 80"
  }
}

resource "aws_subnet" "sevens_private_subnet" {
  vpc_id     = data.aws_vpc.default.id
  cidr_block = cidrsubnets(data.aws_vpc.default.cidr_block,1,16,8)[2]
  
  tags = merge(
    local.common_tags
  )
}

resource "aws_route_table" "sevens_private_rt" {
  vpc_id = data.aws_vpc.default.id
  tags = merge(
    local.common_tags
  )
}

resource "aws_route_table_association" "sevens_private_rta" {
  subnet_id      = aws_subnet.sevens_private_subnet.id
  route_table_id = aws_route_table.sevens_private_rt.id
}
###################################################
########       AUTO SCALING           #############
###################################################
/*
Autoscaling & Launchtemplate definition for Backend Servers
*/

resource "aws_launch_template" "sevens_backend_lt" {
  name        = "${local.application}-${local.environment}-lt"
  description = "${local.application} ${local.environment} Launch Template"
  lifecycle {
    create_before_destroy = true
  }

  update_default_version = true

  block_device_mappings {
    # Root volume
    device_name = "/dev/xvda"
    no_device   = 0
    ebs {
      delete_on_termination = true
      encrypted             = true
      volume_size           = 50
      volume_type           = "gp2"
    }
  }
  disable_api_termination              = true
  image_id                             = data.aws_ami.amazon_linux_2.id
  instance_initiated_shutdown_behavior = "stop"
  instance_type                        = local.api_flavor
  key_name                             = var.key_name
  vpc_security_group_ids               = [aws_security_group.sevens_backend_sg.id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${local.application}-${local.environment}"
      Application = "${local.application}"
    }
  }

  user_data = filebase64("bootstrap.sh")
}


resource "aws_autoscaling_group" "sevens_api_asg" {
  name = "${local.application}-${local.environment}-asg"

  launch_template {
    id      = aws_launch_template.sevens_backend_lt.id
    version = "$Latest"
  }
  vpc_zone_identifier       = [aws_subnet.sevens_private_subnet.id]
  min_size                  = 2
  max_size                  = 3
  desired_capacity          = 2
  target_group_arns         = [aws_lb_target_group.sevens_backend_tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 1000

  timeouts {
    delete = "3m"
  }

  tags = concat([
    {
      key                 = "Application"
      value               = "${local.application}"
      propagate_at_launch = true
    },
    {
      key                 = "Name"
      value               = "${local.application}-${local.environment}"
      propagate_at_launch = true
    }
  ])

  lifecycle {
    create_before_destroy = true
  }
}

###################################################
########       LB AND COMPONENTS      #############
###################################################
/*
Internet facing Application Load balancer
*/
resource "aws_lb" "sevens_portal_alb" {
  name               = "${local.application}-${local.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sevens_alb_sg.id]
  subnets            = data.aws_subnet_ids.default_public_subnet.ids

  enable_deletion_protection = false

  tags = merge(
    local.common_tags
  )
}

/*
Target Group for respective ALB
*/
resource "aws_lb_target_group" "sevens_backend_tg" {
  name     = "${local.application}-${local.environment}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  tags     = local.common_tags
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

/*
Listener for respective ALB
*/
resource "aws_lb_listener" "sevens_portal_listener" {
  load_balancer_arn = aws_lb.sevens_portal_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sevens_backend_tg.arn
  }
  tags = local.common_tags
}

/*
Listener Rule for respective ALB
*/
resource "aws_lb_listener_rule" "sevens_portal_listener_rule" {
  listener_arn = aws_lb_listener.sevens_portal_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sevens_backend_tg.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  tags = local.common_tags
}

###################################################
########       Outputs                #############
###################################################
/*
ALB Url as output
*/
output "lb_url" {
  value = aws_lb.sevens_portal_alb.dns_name
}